require 'forwardable'
require 'kontena/json'

# /v2/keys API client
module Kontena::Etcd::Keys
  include Kontena::Etcd::Logging

  class Response
    extend Forwardable
    include Kontena::JSON::Model

    json_attr :action
    json_attr :node, model: Kontena::Etcd::Node
    json_attr :prev_node, name: 'prevNode', model: Kontena::Etcd::Node

    attr_reader :etcd_index, :raft_index, :raft_term

    def_delegators :@node, :key, :value, :modified_index, :created_index, :expiration, :ttl, :dir, :nodes
    def_delegators :@node, :directory?, :children

    def self.from_http(headers, body)
      response = new(
        etcd_index: Integer(headers['X-Etcd-Index']),
        raft_index: Integer(headers['X-Raft-Index']),
        raft_term: Integer(headers['X-Raft-Term']),
      )
      response.from_json! body
      response
    end

    # @param etcd_index [Integer]
    # @param raft_index [Integer]
    # @param raft_term [Integer]
    # @param **attrs JSON attrs
    def initialize(etcd_index: nil, raft_index: nil, raft_term: nil, **attrs)
      @etcd_index = etcd_index
      @raft_index = raft_index
      @raft_term = raft_term
      super(**attrs)
    end
  end

  def keys_path(key)
    key = '/' + key unless key.start_with? '/'

    return '/v2/keys' + key
  end

  def keys_request(op, key, method:, **opts)
    params = opts[:form] || opts[:query]

    http_response = self.http_request(method, self.keys_path(key), **opts)

    response = Response.from_http(http_response.headers, http_response.body)
    logger.debug {
      path = response.node.key
      path += '/' if response.node.directory?

      if response.node.directory?
        names = response.node.nodes.map{ |node|
          name = File.basename(node.key)
          name += '/' if node.directory?
          name
        }
        "#{op} #{key} #{params}: #{response.action} #{path}@#{response.node.modified_index}: #{names.join ' '}"
      else
        "#{op} #{key} #{params}: #{response.action} #{path}@#{response.node.modified_index}: #{response.node.value}"
      end
    }
    return response
  rescue Excon::Error::HTTPStatus => error
    if error.response.headers['Content-Type'] == 'application/json'
      error = Kontena::Etcd::Error.from_http(error.response.status, error.response.body)

      logger.debug { "#{op} #{key} #{params}: error #{error.class} #{error.reason}@#{error.index}: #{error.message}" }

      raise error
    else
      raise
    end
  end

  # @param key [String]
  # @param opts [Hash] GET query params
  # @raise [Kontena::Etcd::Error]
  # @return [Kontena::Etcd::Keys::Response]
  def get(key, **opts)
    keys_request(:get, key, method: 'GET', query: opts)
  end

  # Modify node with various options altering the behavior.
  #
  # XXX: is the positional value a good idea or just confusing?
  #
  # @param key [String]
  # @param value [String, nil] may also use the `value: ...` option
  # @param opts [Hash] PUT form params
  # @raise [Kontena::Etcd::Error]
  # @return [Kontena::Etcd::Keys::Response]
  def set(key, value = nil, **opts)
    opts[:value] = value if value
    keys_request(:set, key, method: 'PUT', form: opts)
  end

  # Variant of set that leaves the value as-is, but updates the TTL without notifying watchers.
  #
  # @param key [String]
  # @param ttl [Integer]
  # @param opts [Hash] PUT form params
  # @raise [Kontena::Etcd::Error]
  # @return [Kontena::Etcd::Keys::Response]
  def refresh(key, ttl, **opts)
    keys_request(:refresh, key, method: 'PUT', form: {refresh: true, ttl: ttl, prevExist: true, **opts})
  end

  # @param key [String]
  # @param opts [Hash] DELETE query params
  # @raise [Kontena::Etcd::Error]
  # @return [Kontena::Etcd::Keys::Response]
  def delete(key, **opts)
    keys_request(:delete, key, method: 'DELETE', query: opts)
  end

  # @param key [String]
  # @param opts [Hash] POST form params
  # @raise [Kontena::Etcd::Error]
  # @return [Kontena::Etcd::Keys::Response]
  def post(key, **opts)
    keys_request(:post, key, method: 'POST', form: opts)
  end

  # @param key [String]
  # @param opts [Hash] GET query params
  # @raise [Kontena::Etcd::Error]
  # @return [Kontena::Etcd::Keys::Response]
  def watch(key, **opts)
    keys_request(:watch, key, method: 'GET', query: {wait: true, **opts})
  end

  # Helper wrappers

  # Return current etcd index
  #
  # @param key [String]
  # @raise [Kontena::Etcd::Error]
  # @return [Integer]
  def get_index(key: '/')
    get(key).etcd_index
  end

  # Iterate through key => value pairs directly under given preifx
  #
  # @yield [name, node]
  # @yieldparam name [String] node name, without the leading prefix
  # @yieldparam node [Node] node object
  def each(prefix = '/')
    prefix = prefix + '/' unless prefix.end_with? '/'

    response = get(prefix)

    for node in response.node.nodes
      yield node.key[prefix.length..-1], node
    end
  end
end
