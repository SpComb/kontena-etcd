require 'kontena/json'

# Map an object to an etcd path, with a JSON value
module Kontena::Etcd::Model
  # Configure global etcd client to use
  #
  # @param etcd [Etcd::Client]
  def self.etcd=(etcd)
    @@etcd = etcd
  end

  # @return [Etcd::Client]
  def self.etcd
    @@etcd
  end

  # @return [Etcd::Client]
  def etcd
    @@etcd
  end

  # Set operation failed with a conflict
  class Conflict < StandardError

  end

  # Get operation failed from value
  class Invalid < StandardError

  end

  class NotFound < StandardError

  end

  # A structured etcd key path, consisting of String and Symbol components.
  #
  # @attr_reader path [Array<String, Symbol>] normalized path components, which are path-component strings, or symbols for instance variables
  class Schema
    attr_reader :path

    # Normalize path from String to internal @path
    #
    # @raise ArgumentError
    # @param path [String] etcd key schema path definition with :symbol placeholders
    def initialize(path)
      raise ArgumentError, "etcd_key path must start with a /" unless path.start_with? '/'

      # normalize to an Array of Strings and Symbols
      @path = path[1..-1].split('/', -1).map { |part|
        if part.empty?
          raise ArgumentError, "invalid path component: #{part}"
        elsif part.start_with? ':'
          part[1..-1].to_sym
        else
          part
        end
      }
    end

    # Returns string representation of schema path, with symbol placeholders.
    #
    # @return [String]
    def to_s
      '/' + @path.map { |part|
        if part.is_a? String
          part
        elsif part.is_a? Symbol
          part.inspect
        else
          fail "Invalid path part: #{part}"
        end
      }.join('/')
    end

    # Yield each key symbol for object.
    #
    # @return [Array<String>] key values
    def each_key()
      for part in @path
        if part.is_a? String

        elsif part.is_a? Symbol
          yield part
        else
          raise "Invalid path part: #{part}"
        end
      end
    end

    # Yield each key-value pair for given values.
    #
    # @param key_values [Array<String>] key values for etcd path
    # @yield [sym, value]
    # @yieldparam sym [Symbol] instance variable symbol for key
    # @yieldparam value [String] instance variable value for key
    def each_key_value(*values)
      each_key do |sym|
        value = values.shift

        raise ArgumentError, "Missing key argument for #{sym.inspect}" unless value
        raise ArgumentError, "Empty key value for #{sym}" if value.empty?

        yield sym, value
      end

      raise ArgumentError, "Extra key arguments" unless values.empty?
    end

    # Returns full etcd path for object, using key values from instance variables.
    #
    # @yield [sym] Get key instance variable values
    # @yieldparam sym [Symbol] key instance variable name
    # @yieldreturn [String] etcd key value
    # @return [String] etcd path
    def path_with_keys()
      path = []

      for part in @path
        if part.is_a? String
          path << part
        elsif part.is_a? Symbol
          path << (yield part)
        else
          raise "Invalid path part: #{part}"
        end
      end
      '/' + path.join('/')
    end

    # Returns as much of the leading path as possible, for the given number of keys.
    # If the full set if keys is given, returns a full path.
    # If a partial set of keys is given, returns a directory path ending in /
    #
    # @param key [String] key values, may be shorter than the full key
    # @raise ArgumentError if an invalid key value is given, or if too many keys are given
    # @return [String] etcd path, ending in / for a partial prefix
    def prefix(*key)
      path = []
      partial = false

      for part in @path
        if part.is_a? String
          path << part
        elsif part.is_a? Symbol
          if key.empty?
            partial = true
            break
          else
            part = key.shift

            # guard against accidential broad prefixes
            raise ArgumentError, "Invalid key prefix value: #{part}" if part.nil? || part.empty?

            path << part
          end
        else
          raise "Invalid path part: #{part}"
        end
      end

      raise ArgumentError, "Etcd key is too long" if !key.empty?

      if partial
        '/' + path.join('/') + '/'
      else
        '/' + path.join('/')
      end
    end

    # Parse key values from full etcd path
    #
    # @param node_path [String] etcd path
    # @return [Array<String>] key values
    def parse(path)
      path = path[1..-1] while path.start_with? '/' # lstrip '/'
      path = path.split('/')
      key = []
      for part in @path
        value = path.shift

        if part.is_a? String
          raise "Incorrect path for #{self} at #{value}: should be #{part}" unless value == part
        elsif part.is_a? Symbol
          key << value
        else
          raise "Invalid path part: #{part}"
        end
      end
      key
    end
  end

  module ClassMethods
    # Global Kontena::Etcd::Client
    #
    # @return [Kontena::Etcd::Client]
    def etcd
      Kontena::Etcd::Model.etcd
    end

    # Define the etcd key schema used for object identity. This is an absolute path-like
    # string, starting from the root, with :symbol placeholders for instance variables.
    # This is normalized into a flattened array of String and Symbol components.
    #
    # Any symbols in the etcd_path are added as (readonly) instance attributes.
    #
    # This is required for a Model class, and any operations on the class will raise a RuntimeError otherwise.
    #
    # @param path [Array<String, Symbol>]
    def etcd_path(path)
      @etcd_schema = Schema.new(path)

      @etcd_schema.each_key do |sym|
        self.send :attr_reader, sym
      end
    end

    # Return Schema defined by #etcd_path
    #
    # @see #etcd_path
    # @raise [RuntimeError] if no etcd_path
    # @return [Kontena::Etcd::Model::Schema]
    def etcd_schema
      raise "Missing etcd_path for #{self}" unless @etcd_schema

      @etcd_schema
    end


    # Return object from etcd node
    #
    # @param node [Etcd::Node]
    # @return [EtcdModel]
    def load(node)
      key = etcd_schema.parse(node.key)
      object = new(*key)
      object.from_json!(node.value)
      object
    end

    public

    # Create directory for objects under the given partial key prefix.
    # Idempotent, does nothing if the directory already exists.
    #
    # For safety, every key value is checked to be non-nil and non-empty.
    #
    # @raise ArgumentError if any invalid keys are given
    # @param key [String] key values
    def mkdir(*key)
      prefix = etcd_schema.prefix(*key)

      raise ArgumentError, "mkdir for complete object key" unless prefix.end_with? '/'

      etcd.set(prefix, dir: true, prevExist: false)
    rescue Kontena::Etcd::Error::NodeExist => errors
      # XXX: the same error is returned if the path exists as a file
      return
    end

    # Create and return new object in etcd, or raise Conflict if already exists
    #
    # @param key [Array<String>] object key values
    # @param opts [Hash<String, Object>] object attribute values
    # @raise [Conflict] object already exists
    # @return [EtcdModel] stored instance
    def create(*key, **opts)
      object = new(*key, **opts)
      object.create!
      object
    rescue Kontena::Etcd::Error::NodeExist => error
      raise const_get(:Conflict), "Create conflict with #{error.reason}@#{error.index}: #{error.message}"
    end

    # Return object from etcd, or nil if not exists
    #
    # @param name [String] object key name
    # @return [EtcdModel] loaded instance, or nil if not exists
    def get(*key)
      object = new(*key)
      object.get!
      object
    rescue Kontena::Etcd::Error::KeyNotFound
      nil
    end

    # Create and return new object in etcd, or return existing object.
    #
    # The returned object is guaranteed to have the same key values, but may have different attribute values.
    #
    # @param key [Array<String>] object key values
    # @param opts [Hash<String, Object>] object attribute values
    # @raise [Conflict] if the create races with a delete
    # @return [EtcdModel] stored instance
    def create_or_get(*key, **attrs)
      begin
        object = create(*key, **attrs)
        object
      rescue const_get(:Conflict) => error
        object = new(*key, **attrs)
        object.get!
        object
      end
    rescue Kontena::Etcd::Error::KeyNotFound => error
      raise const_get(:Conflict), "Create-and-Delete conflict with #{error.reason}@#{error.index}: #{error.message}"
    end

    def _enumerate(y, key)
      prefix = etcd_schema.prefix(*key)
      response = etcd.get(prefix)

      for node in response.children
        name = node.key[prefix.length..-1]
        node_key = key + [name]

        if node.directory?
          _enumerate(y, node_key)
        else
          object = new(*node_key)
          object.load!(node)

          y << object
        end
      end
    rescue Kontena::Etcd::Error::KeyNotFound
      # directory does not exist, it is empty
    end

    # Recursively enumerate all etcd objects under the given (partial) key prefix.
    #
    # Considers the directory to be empty if it does not exist.
    #
    def objects(*key)
      Enumerator.new do |y|
        _enumerate(y, key)
      end
    end

    # Iterate over all objects under the given (partial) key prefix
    #
    # @param key [String] key values
    # @yield [object]
    # @yieldparam object [EtcdModel]
    def each(*key, &block)
      objects(*key).each(&block)
    end

    # List all objects under the given (partial) key prefix
    #
    # @param key [String] key values
    # @return [Array<EtcdModel>]
    def list(*key)
      objects(*key).to_a
    end

    # Delete all objects under the given (partial) key prefix.
    #
    # Call without arguments to delete everything under the initial prefix of this class.
    # Any other class objects sharing the same common prefix as this class will also be deleted.
    #
    # For safety, every key value is checked to be non-nil and non-empty.
    #
    # @raise ArgumentError if any invalid keys are given
    # @param key [String] key values
    def delete(*key)
      prefix = etcd_schema.prefix(*key)

      etcd.delete(prefix, recursive: prefix.end_with?('/'))
    rescue Kontena::Etcd::Error::KeyNotFound => error
      raise const_get(:NotFound), "Removing non-existant node #{error.reason}@#{error.index}: #{error.message}"
    end

    # Delete an empty directory under the given (partial) key prefix.
    #
    # The directory must not have any nodes
    def rmdir(*key)
      prefix = etcd_schema.prefix(*key)

      raise ArgumentError, "rmdir for complete object key" unless prefix.end_with? '/'

      etcd.delete(prefix, dir: true)
    rescue Kontena::Etcd::Error::KeyNotFound => error
      raise const_get(:NotFound), "Removing non-existant directory #{error.reason}@#{error.index}: #{error.message}"
    rescue Kontena::Etcd::Error::DirNotEmpty => error
      raise const_get(:Conflict), "Removing non-empty directory #{error.reason}@#{error.index}: #{error.message}"
    end

    # Watch all objects under the given (partial) key prefix.
    #
    # XXX: the prefix must only contain model nodes
    #
    # @yield [objects]
    # @yieldparam objects [Hash{String => Model}]
    def watch(*key, &block)
      reader = Kontena::Etcd::Reader.new(etcd_schema.prefix(*key)) do |node|
        # XXX: skip objects that do not match the schema
        object = new(*etcd_schema.parse(node.key))
        object.load! node unless node.value.nil? # do not load when deleted
      end

      reader.run(&block)
    end
  end

  def self.included(base)
    raise TypeError, "Must include Kontena::JSON::Model before including Kontena::Etcd::Model" unless base.ancestors.include? Kontena::JSON::Model

    base.extend(ClassMethods)

    # define per-model Errors
    base.const_set :Conflict, Class.new(Conflict)
    base.const_set :Invalid, Class.new(Invalid)
    base.const_set :NotFound, Class.new(NotFound)
  end

  attr_accessor :etcd_node

  # Initialize from etcd key :sym placeholder values, and value attributes
  #
  # @param keys [Array<String>] EtcdModel key values
  # @param attrs [Hash<Symbol, EtcdModel>] JSONModel attribute values
  def initialize(*keys, **attrs)
    @etcd_node = nil

    super(**attrs)

    self.class.etcd_schema.each_key_value(*keys) do |sym, value|
      self.instance_variable_set("@#{sym}", value)
    end
  end

  # Compare for equality based on etcd key and value mixin
  #
  # @param other [EtcdModel]
  # @return [Boolean]
  def <=>(other)
    if self.etcd_key != other.etcd_key
      return self.etcd_key <=> other.etcd_key
    else
      return super
    end
  end

  include Comparable

  # Compute etcd path, using etcd node, or compuated key value from schema and initialize args
  #
  # @return [String] etcd path, with key values
  def etcd_key
    if @etcd_node
      @etcd_node.key
    else
      self.class.etcd_schema.path_with_keys do |sym|
        self.instance_variable_get("@#{sym}")
      end
    end
  end

  # Get etcd index when this node was created or last modified
  def etcd_index
    @etcd_node.modified_index
  end

  # Load object from etcd node
  #
  # Updates all JSON attribute values.
  #
  # @raise [Invalid]
  def load!(node)
    @etcd_node = node

    if node.directory?
       raise self.class.const_get(:Invalid), "Node is a directory"
     end

    from_json!(node.value)
  rescue JSON::ParserError => error
    raise self.class.const_get(:Invalid), "Invalid JSON value: #{error}"
  end

  # Test if this node has been modified after the given index
  def etcd_modified?(after_index: nil)
    if after_index && @etcd_node.modified_index > after_index
      return true
    end
    return false
  end

  # Get this objcet from etcd.
  #
  # Updates all JSON attribute values.
  #
  # @raise Etcd::KeyNotFound
  def get!
    load!(etcd.get(etcd_key).node)
  end

  # Create this object in etcd, raising if the object already exists.
  #
  # @raise Etcd::NodeExist
  def create!
    @etcd_node = etcd.set(etcd_key, self.to_json, prevExist: false).node
  end

  # Update this object in etcd, raising if the object does not exist.
  #
  # @raise ...
  def update!
    @etcd_node = etcd.set(etcd_key, self.to_json, prevExist: true).node
  end

  # Delete this object in etcd, raising if the object does not exist.
  #
  # @raise ...
  def delete!
    # delete changes the node.modified_index
    @etcd_node = etcd.delete(etcd_key).node
  end
end
