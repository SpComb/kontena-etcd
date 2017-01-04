require 'sinatra'

# Fake etcd /v2/keys API implementation for application testing.
#
# You can use #load() to initialize the database, and then use the #api() as a client endpoint.
# Afterwards, use #modified(), #to_nodes() and #to_dirs() to check the end state.
#
# ## Implemented:
# * GET /version
# * GET/v2/keys/*
# ** For key and directories
# * GET /v2/keys/*?recursive=true
# * PUT /v2/keys/*?dir=true
# * PUT /v2/keys/* value=...
# * PUT /v2/keys/*?prevExist=false value=...
# * PUT /v2/keys/*?prevExist=true value=...
# * DELETE /v2/keys/*
# * DELETE /v2/keys/*?dir=true
# * DELETE /v2/keys/*?recursive=true
#
# ## Unimplemented
# * set prevIndex, prevValue
# * delete prevIndex, prevValue
# * error index
# * node created/modified index
# * HTTP X-Etcd-Index headers
# * HTTP X-Raft-Index, X-Raft-Term
# * TTL
#
# Usage example:
=begin

describe Application do
  let :etcd_server do
    Etcd::FakeServer.new()
  end

  let :etcd do
    EtcdClient.new()
  end

  before do
    stub_request(:any, /localhost:2379/).to_rack(etcd_server.api)

    EtcdModel.etcd = etcd

    etcd_server.load(
      '/test' => { 'value' => 'foobar' }
    )
  end

  it 'gets the value from etcd' do
    expect(etcd.get('/test').value).to eq 'foobar'
  end
end
=end
module Kontena::Etcd::Test
  class FakeServer < ServerBase
    class Node
        attr_reader :key, :created_index, :modified_index, :value, :nodes, :expire

        def initialize(key, index, value: nil, nodes: nil, expire: nil)
          @key = key
          @created_index = index
          @modified_index = index
          @value = value
          @nodes = nodes
          @expire = expire
        end

        def parent_path
          File.dirname(key)
        end

        def directory?
          @nodes != nil
        end

        def update(index, value, expire: nil)
          @modified_index = index
          @value = value
          @expire = expire
        end
        def delete(index)
          @modified_index = index
          @nodes = {} if @nodes
        end

        # @raise [TypeError] if not a directory
        def link(node)
          # @nodes will be nil if not a directory
          @nodes[node.key] = node
        end
        def unlink(node)
          @nodes.delete(node.key)
        end

        def serialize(recursive: false, toplevel: true)
          obj = {
            'key' => @key,
            'createdIndex' => @created_index,
            'modifiedIndex' => @modified_index,
          }

          if directory?
            obj['dir'] = true

            if recursive || toplevel
              obj['nodes'] = nodes.map{ |key, node| node.serialize(recursive: recursive, toplevel: false) }
            end
          else
            obj['value'] = @value
          end

          return obj
        end

        def to_json(*args)
          serialize.to_json(*args)
        end
    end

    class Error < StandardError
      attr_reader :status

      def initialize(status, code, key)
        @status = status
        @code = code
        @key = key
      end

      def to_json(*args)
        {
            'errorCode' => @code,
            'cause' => @key,
            'index' => 0,
            'message' => message,
        }.to_json(*args)
      end
    end

    protected

    def initialize(*args)
      super
      reset!
    end

    # Link the directory node at the given path with the given child node
    # @return [Node] directory node
    def mkdir(path)
      @nodes[path] ||= Node.new(path, @index, nodes: {})
    end

    # Lookup a key
    def read(key)
      key = key.chomp('/')
      key = '/' + key unless key.start_with? '/'

      return key, @nodes[key]
    end

    # Write a node
    def write(path, ttl: nil, **attrs)
      @index += 1

      @nodes[path] = node = Node.new(path, @index, expire: ttl ? @clock + ttl : nil, **attrs)

      # create parent dirs
      child = node
      until child.key == '/'
        parent = mkdir(child.parent_path)
        parent.link(child)
        child = parent
      end

      node
    end

    def update(node, value, ttl: nil)
      @index += 1

      node.update(@index, value, expire: ttl ? @clock + ttl : nil)
    end

    # recursively unlink node and any child nodes
    def unlink(node)
      @nodes.delete(node.key)

      if node.directory?
        for key, node in node.nodes
          unlink(node)
        end
      end
    end

    def remove(node)
      @index += 1

      # unlink from parent
      @nodes[node.parent_path].unlink(node)

      # remove from @nodes
      unlink(node)

      # mark node as deleted
      node.delete(@index)
    end

    # Log an operation
    def log!(action, node)
      path = node.key
      path += '/' if node.directory?

      @logs << [action, path]
    end

    # Yield all nodes under root
    def walk
      for key, node in @nodes
        next unless key.start_with? @root

        yield node
      end
    end

    public

    # Reset database to empty state for key
    #
    # Initializes an empty database.
    def reset!
      @index = 0
      @nodes = {}
      @logs = []
      @modified = false
      @clock = 0.0

      mkdir('/')
      @start_index = @index
    end

    # Load a hash of nodes into the store.
    # Encodes any JSON objects given as values
    # Creates any directories as needed.
    #
    # @param tree [Hash<String, Object or String>]
    # @return [Integer] etcd index after loading
    def load!(tree)
      load_nodes(tree) do |key, value|
        if value == :directory
          write key, nodes: {}
        else
          write key, value: value
        end
      end
      @start_index = @index
    end

    # Advance clock and expire nodes
    def tick!(offset)
      @clock += offset

      walk do |node|
        next unless node.expire && @clock >= node.expire

        remove(node)
        log! :expire, node
      end
    end

    def start_index
      @start_index
    end

    def modified?
      @index > @start_index
    end

    def logs
      @logs
    end

    public

    def version
      {
        'etcdserver' => '0.0.0',
        'etcdcluster' => '0.0.0',
      }
    end

    def index
      @index
    end

    def get(key, recursive: nil, wait: false, waitIndex: nil)
      key, node = read(key)

      raise Error.new(404, 100, key), "Key not found" unless node
      raise Error.new(400, 401, key), "No support for watch history" if wait

      return {
        'action' => 'get',
        'node' => node.serialize(recursive: recursive),
      }
    end

    def set(key, dir: nil, value: nil, ttl: nil, refresh: nil, prevExist: nil, prevIndex: nil, prevValue: nil)
      key, node = read(key)

      raise Error.new(400, 211, key), "Value provided on refresh" if refresh && value
      raise Error.new(400, 212, key), "A TTL must be provided on refresh" if refresh && !ttl

      if node
        raise Error.new(412, 105, key), "Key already exists" if prevExist == false
        raise Error.new(403, 102, key), "Not a file" if dir

        if prevIndex || prevValue
          raise Error.new(412, 101, key), "Compare index failed" if prevIndex && node.modified_index != prevIndex
          raise Error.new(412, 101, key), "Compare value failed" if prevValue && node.value != prevValue

          action = :compareAndSwap
        else
          action = :set
        end

        prev_node = node.serialize
        value = node.value if refresh

        update node, value, ttl: ttl

        log! action, node unless refresh
      else
        raise Error.new(404, 100, key), "Key not found" if refresh || prevExist == true || prevIndex || prevValue

        action = prevExist == false ? :create : :set
        prev_node = nil

        node = if dir
          write key, nodes: {}, ttl: ttl
        else
          write key, value: value, ttl: ttl
        end

        log! action, node
      end

      return {
        'action' => action,
        'node' => node.serialize,
        'prevNode' => prev_node,
      }
    end

    def delete(key, recursive: nil, dir: nil)
      key, node = read(key)

      if !node
        raise Error.new(404, 100, key), "Key not found"
      elsif node.directory? && !dir && !recursive
        raise Error.new(403, 102, key), "Not a file"
      elsif node.directory? && dir && !node.nodes.empty? && !recursive
        raise Error.new(403, 108, key), "Directory not empty"
      end

      log! :delete, node

      remove(node)

      return {
        'action' => 'delete',
        'node' => node,
        'prevNode' => node,
      }
    end

    def api
      API.new(self)
    end

    class API < Sinatra::Base
      def initialize(server)
        super
        @server = server
      end

      def param_bool(name)
        case params[name]
        when nil
           nil
        when 'true', '1'
          true
        when 'false', '0'
          false
        else
          raise Error.new(400, 209, "invalid value for #{name}"), "Invalid field"
        end
      end

      def param_int(name)
        case value = params[name]
        when nil
          nil
        else
          # XXX: HTTP 400
          Integer(value)
        end
      end

      def respond(status, object)
        headers = {
          'Content-Type' => 'application/json',
          'X-Etcd-Index' => @server.index,
          'X-Raft-Index' => 0,
          'X-Raft-Term' => 0,
        }
        return status, headers, object.to_json
      end

      get '/version' do
        begin
          respond 200, @server.version
        rescue Error => error
          respond error.status, error
        end
      end

      get '/v2/keys/*' do |key|
        begin
          respond 200, @server.get(key,
            recursive: param_bool('recursive'),
            wait: param_bool('wait'),
            waitIndex: param_int('waitIndex'),
          )
        rescue Error => error
          respond error.status, error
        end
      end

      put '/v2/keys/*' do |key, value: nil|
        begin
          respond 201, @server.set(key,
            prevExist: param_bool('prevExist'),
            prevIndex: param_int('prevIndex'),
            prevValue: params['prevValue'],
            dir: param_bool('dir'),
            value: params['value'],
            ttl: param_int('ttl'),
            refresh: param_bool('refresh'),
          )
        rescue Error => error
          respond error.status, error
        end
      end

      delete '/v2/keys/*' do |key|
        begin
          respond 200, @server.delete(key,
            recursive: param_bool('recursive'),
            dir: param_bool('dir'),
          )
        rescue Error => error
          respond error.status, error
        end
      end
    end
  end
end
