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
    @shared = { }

    logger.debug "connected to etcd=#{@client.uri} with version=#{@client.version}"
  end

  # @return [Integer, nil]
  def ttl
    @ttl
  end

  def [](key)
    return @nodes[key]
  end

  def shared?(key)
    return @shared[key]
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

    @nodes.each do |key, node|
      if !nodes[key]
        remove(node)

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
      response = @client.refresh(key, @ttl, prevValue: node.value)
      shared_expiration = @shared[key]

      if response.prev_node.modified_index != node.modified_index
        shared_node = response.prev_node

        if !shared_expiration
          # log when node becomes shared
          logger.warn "share node=#{node.key}@#{shared_node.modified_index}"
        end

        # updated shared state
        @shared[key] = shared_node.expiration

      elsif shared_expiration && shared_expiration < response.date
        logger.warn "expire shared node=#{key} at #{shared_expiration} < #{response.date}"

        @shared.delete(key)
      end

      @nodes[key] = response.node
    end
  end

  # Clear any written nodes from etcd
  def clear
    @nodes.each do |key, node|
      remove(node)
    end
    @nodes = { }
  end

  protected

  # Remove node from etcd, if it is exclusively written by us
  def remove(node)
    # TODO: re-test shared expiration without refresh?
    if @shared[node.key]
      logger.info "skip shared #{node.key}"

      return
    end

    logger.info "delete #{node.key}@#{node.modified_index}"

    @client.delete(node.key, prevIndex: node.modified_index)
  rescue Kontena::Etcd::Error::TestFailed => error
    logger.warn "delete node=#{node.key}@#{node.modified_index}: #{error}"
  end
end
