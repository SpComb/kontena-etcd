# Watch a set of etcd nodes under the given key prefix.
#
# First call sync, and then loop on watch.
#
# @attr nodes [Hash{String => Model}]
class Kontena::Etcd::Reader
  include Kontena::Etcd::Logging

  # @see #sync
  def initialize(prefix, &loader)
    @prefix = prefix
    @loader = loader
    @client = Kontena::Etcd::Client.new

    # call #sync to start
    @index = @nodes = nil

    logger.debug "Connected to etcd=#{@client.uri} with version=#{@client.version}"
  end

  # Load initial state from etcd
  def sync
    @nodes = { }

    response = @client.get(@prefix, recursive: true)

    response.node.walk do |node|
      if object = self.load(node)
        update! node.key, object
      end
    end

    @index = response.etcd_index
  end

  # Watch for a change from etcd.
  #
  # @raise [Kontena::Etcd::Error::EventIndexCleared] must restart from sync
  def watch
    response = @client.watch(@prefix, recursive: true, waitIndex: @index + 1)
    object = self.load(response.node)

    logger.info "#{response.action} #{response.key}: #{object.to_json}"

    self.apply! response.key, response.action, object

    @index = response.node.modified_index
  end

  # Sync and then continuously watch for changes, yielding.
  #
  # Handles re-sync on EventIndexCleared.
  #
  # @yield [reader]
  # @yieldparam reader [Kontena::Etcd::Reader]
  def run(&block)
    self.sync

    yield self

    loop do
      self.watch

      yield self
    end
  rescue Kontena::Etcd::Error::EventIndexCleared => error
    retry
  end

  # Internal interface
  protected

  # Load object from node, optionally using @loader
  def load(node)
    if @loader
      return @loader.call(node)
    else
      return node
    end
  end

  def update!(key, object)
    if object
      object.freeze

      @nodes[key] = object
    else
      @nodes.delete(key)
    end
  end

  def apply!(key, action, object = nil)
    case action
    when 'create', 'set', 'update'
      update! key, object
    when 'delete', 'expire'
      update! key, nil
    else
      raise "Unkown etcd action=#{action} on key=#{key}"
    end
  end

  # Enumerable interface
  public

  include Enumerable

  def each(&block)
    @nodes.each_value(&block)
  end

  def [](key)
    @nodes[key]
  end

  def to_h
    @nodes.clone
  end

  def size
    @nodes.size
  end
end
