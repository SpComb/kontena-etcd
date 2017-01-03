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

    # Return current etcd index. This increments on each modification?
    #
    # @return [Integer]
    def get_index
      return @client.get(@root).etcd_index
    rescue Kontena::Etcd::Error::KeyNotFound => error
      return nil
    end

    # Uses etcd GET ?wait to yield modifications after from index up to and including to index
    def get_logs(index, to)
      while index < to
        response = @client.watch(@root, recursive: true, waitIndex: index + 1, timeout: 1.0)

        yield response.action, response.node

        index = response.node.modified_index
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
    def load!(tree)
      load_nodes(tree) do |key, value|
        if value == :directory
          response = @client.set(key, dir: true)
        else
          response = @client.set(key, value)
        end

        # record initial load index for modfied?
        @etcd_reset = false
        @etcd_index = response.etcd_index
      end
    end

    # Return the initial un-modified etcd index after the load!
    def etcd_index
      @etcd_index
    end

    # Has the store been modified since reset()?
    #
    # This does not count failed set operations
    #
    # @return [Boolean]
    def modified?
      etcd_index = self.get_index

      if @etcd_reset
        # reset, not loaded, should not exist
        return !etcd_index.nil?
      elsif etcd_index.nil?
        # reset, loaded, deleted
        return true
      else
        # reset, loaded, still exists
        return etcd_index > @etcd_index
      end
    end

    # Operations log
    def logs
      etcd_index = get_index

      return nil if @etcd_index.nil? || etcd_index.nil?

      logs = []
      get_logs(@etcd_index, etcd_index) do |action, node|
        path = node.key
        path += '/' if node.directory?

        logs << [action.to_sym, path]
      end
      logs
    end
  end
end
