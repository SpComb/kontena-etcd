module Kontena::Etcd::Test
  # etcd adapter for managing an etcd server for tests
  class TestServer < ServerBase
    protected

    def initialize(root, env = ENV)
      super(root)
      @client = Kontena::Etcd::Client.from_env(env)
    end

    # Recursive walk over nodes
    def walk_node(node, &block)
      yield node

      if node.directory?
        for node in node.children
          walk_node(node, &block)
        end
      end
    end

    # Yield all etcd nodes under @root, recursively
    #
    def walk(&block)
      root = @client.get(@root, recursive: true)

      walk_node(root, &block)
    rescue Kontena::Etcd::Error::KeyNotFound
      # empty
    end

    # End the test, returning a final etcd index.
    #
    # The returned etcd index is guaranteed to be immediately waitable.
    #
    # Returns nil if the root does not exist.
    #
    # @return [Integer, nil]
    def end!
      @end_index ||= @client.set(@root, dir: true, prevExist: true).node.modified_index
    rescue Kontena::Etcd::Error::KeyNotFound => error
      return nil
    end

    # Uses etcd GET ?wait to yield modifications after from index up to index (exclusive)
    def get_logs(index, to)
      while index + 1 < to
        response = @client.watch(@root, recursive: true, waitIndex: index + 1, timeout: 1.0)

        index = response.node.modified_index

        if index < to
          yield response.action, response.node
        else
          # when refreshing, a wait will return the final #touch_index action
          return
        end
      end
    rescue Net::ReadTimeout => error
      fail "Unexpected end of watch stream at #{index} before #{to}"
    end

    public

    # Clear the etcd server database.
    #
    # Used before the each test
    def reset!
      response = @client.delete(@root, recursive: true)

      # record initial reset index for modfied?
      @etcd_reset = true
      @etcd_index = response.etcd_index

    rescue Kontena::Etcd::Error::KeyNotFound => error
      @etcd_reset = true
      @etcd_index = error.index
    end

    # Load a hash of nodes into the store.
    # Encodes any JSON objects given as values
    # Creates any directories as needed.
    #
    # @param tree [Hash<String, Object or String>]
    # @return [Integer] etcd index after loading
    def load!(tree)
      load_index = nil

      load_nodes(tree) do |key, value|
        if value == :directory
          response = @client.set(key, dir: true)
        else
          response = @client.set(key, value)
        end

        load_index = response.etcd_index
      end

      if load_index
        # record initial load index for modfied?
        @etcd_reset = false
        @etcd_index = load_index
      end

      return load_index
    end

    def start_index
      @etcd_index
    end

    # Has the store been modified since reset()?
    #
    # This does not count failed set operations
    #
    # @return [Boolean]
    def modified?
      end_index = self.end!

      if @etcd_reset
        # reset, not loaded, should not exist
        return !end_index.nil?

      elsif end_index.nil?
        # reset, loaded, deleted
        return true
      else
        # reset, loaded, still exists
        # offset by -1 because end! touched it
        return end_index - 1 > @etcd_index
      end
    end

    # Operations log
    def logs
      raise "logs without reset!" unless @etcd_index

      # touch to get a guaranteed final etcd index to watch, even in the case of refresh operations
      end_index = self.end!

      # force-create for watch if missing
      end_index = @client.set(@root, dir: true, prevExist: false).created_index unless end_index

      logs = []
      get_logs(@etcd_index, end_index) do |action, node|
        path = node.key
        path += '/' if node.directory?

        logs << [action.to_sym, path]
      end
      logs
    end
  end
end
