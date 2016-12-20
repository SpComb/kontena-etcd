module Etcd::Keys
  # Iterate through key => value pairs directly under given preifx
  #
  # @yield [name, node]
  # @yieldparam name [String] node name, without the leading prefix
  # @yieldparam node [Node] node object
  def each(prefix = '/')
    prefix = prefix + '/' unless prefix.end_with? '/'

    response = get(prefix)

    for node in response.children
      yield node.key[prefix.length..-1], node
    end
  end

  # Create or update a new key
  def set(key, **opts)
    response = api_execute(key_endpoint + key, :put, params: opts)
    Etcd::Response.from_http_response(response)
  end

  # Refresh an existing key with a new TTL
  def refresh(key, ttl)
    set(key, refresh: true, ttl: ttl, prevExist: true)
  end
end
