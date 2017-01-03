# Maintain a set of nodes in etcd.
#
# Call update with the full set of nodes each time to create/set/delete etcd
# nodes as needed.
#
# Nodes can be written with a TTL, which ensures that stale nodes are cleaned up
# if the writer crashes. Using a TTL requires periodically calling refresh to
# maintain the nodes in etcd.
class Kontena::Etcd::Writer
  include Kontena::Etcd::Logging

  def initialize(ttl: nil)
    @nodes = { }
    @client = Kontena::Etcd::Client.from_env
    @ttl = ttl

    logger.debug "connected to etcd=#{@client.uri} with version=#{@client.version}"
  end

  # @return [Integer, nil]
  def ttl
    @ttl
  end

  # Update set of path => value nodes to etcd
  def update(nodes)
    nodes.each_pair do |key, value|
      if !(node = @nodes[key]) || value != node.value
        logger.info "set #{key}: #{value}"

        response = @client.set(key, value, ttl: @ttl)

        @nodes[key] = response.node
      end
    end

    @nodes.each do |key, value|
      if !nodes[key]
        logger.info "delete #{key} (#{value})"

        @client.delete(key)
        @nodes.delete(key)
      end
    end
  end

  # Refresh currently active etcd nodes
  #
  # Only applicable when using a TTL
  #
  # @raise [Kontena::Etcd::Error::KeyNotFound] node has already expired before we refresh it
  # @raise [Kontena::Etcd::Error::TestFailed] node has been modified
  def refresh
    raise ArgumentError, "Refresh without TTL" unless @ttl

    @nodes.each do |key, node|
      # value should not change
      @nodes[key] = @client.refresh(key, @ttl, prevValue: node.value).node
    end
  end

  # Clear any written nodes from etcd
  def clear
    @nodes.each do |key, value|
      @client.delete(key)
    end
    @nodes = { }
  end
end
