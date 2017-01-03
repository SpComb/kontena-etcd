require 'json'

# Map a Class with instance variables to/from a JSON-encoded object.
module Kontena::JSON
  # A single JSON-encodable/decodable attribute with an object value
  class Attribute
    attr_reader :name, :default, :model

    # Initialize from class declaration
    #
    # @param sym [Symbol] instance variable name
    # @param name [String] override JSON object attribute
    # @param type [Class] convert from basic JSON value to object value using type.new(...)
    # @param model [Class<Kontena::JSON::Model>] load nested model
    # @param omitnil [Boolean] omit from JSON if nil
    # @param default [Object] default value. Used for both load() and initialize()
    def initialize(cls, sym, name: nil, type: nil, model: nil, array_model: nil, omitnil: false, default: nil)
      @class = cls
      @sym = sym
      @name = name || sym.to_s
      @type = type
      @model = model
      @array_model = array_model
      @omitnil = omitnil
      @default = default
    end

    # Store attribute value to JSON object for encoding
    #
    # @param object [Hash] JSON object for encoding
    # @param value [Object] attr value of type
    def store(object, value)
      return if @omitnil && value == nil

      object[@name] = value # will later call .to_json
    end

    # Load attribute value from decoded JSON object
    #
    # @param object [Hash] decoded JSON object
    # @return [Object] of type
    def load(object)
      value = object.fetch(@name, @default)

      if value.nil?
        # TODO: required?
      elsif @type
        value = @type.new(value)
      elsif @model
        value = @model.load_json value
      elsif @array_model
        value = value.map{|array_value| @array_model.load_json array_value }
      end

      value
    rescue => error
      raise error.class, "Loading #{@class}@#{@sym}: #{error}"
    end
  end

  module Model
    module ClassMethods
      # Declared JSON attributes
      #
      # @return [Hash<Symbol, JSONAttr>]
      def json_attrs
        @json_attrs ||= {}
      end

      # Inherit json attrs to subclass
      def inherited(subclass)
        super
        subclass.json_attrs.merge! json_attrs
      end

      # Return decoded JSON object
      #
      # @param object [Hash] JSON-decoded object
      # @param **opts Additional non-JSON initializer options
      # @raise JSON::JSONError
      # @return [Class<Kontena::JSON::Model>] new value with JSON attrs set
      def load_json(object, **opts)
        obj = new(**opts)
        obj.load_json!(object)
        obj
      end

      # Return decoded JSON object
      #
      # @param value [String] JSON-encoded object
      # @param **opts Additional non-JSON initializer options
      # @raise JSON::JSONError
      # @return [Class<Kontena::JSON::Model>] new value with JSON attrs set
      def from_json(value, **opts)
        obj = new(**opts)
        obj.from_json!(value)
        obj
      end

      protected

      # Declare a JSON object attribute using the given instance variable Symbol
      #
      # @see JSONAttr
      # @param sym [Symbol] instance variable
      # @param opts [Hash] JSONAttr options
      def json_attr(sym, readonly: false, **options)
        @json_attrs ||= {}
        @json_attrs[sym] = Attribute.new(self, sym, **options)

        if readonly
          attr_reader sym
        else
          attr_accessor sym
        end
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    # Initialize JSON instance variables from keyword arguments
    def initialize(**attrs)
      attrs.each do |sym, value|
        raise ArgumentError, "Extra JSON attr argument: #{sym.inspect}" unless self.class.json_attrs[sym]
      end

      self.class.json_attrs.each do |sym, json_attr|
        self.instance_variable_set("@#{sym}", attrs.fetch(sym, json_attr.default))
      end
    end

    include Comparable

    # Compare equality of JSON attributes, per the <=> operator
    # @return [Integer] <0, 0, >0
    def <=>(other)
      self.class.json_attrs.each do |sym, json_attr|
        self_value = self.instance_variable_get("@#{sym}")
        other_value = other.instance_variable_get("@#{sym}")

        if self_value.nil? && other_value.nil?
          next
        elsif self_value.nil?
          return -1
        elsif other_value.nil?
          return +1
        elsif self_value != other_value
          return self_value <=> other_value
        end
      end
      return 0
    end

    # Serialize to encoded JSON object
    #
    # @return [String] JSON-encoded object
    def to_json(*args)
      object = {}

      self.class.json_attrs.each do |sym, json_attr|
        json_attr.store(object, self.instance_variable_get("@#{sym}"))
      end

      object.to_json(*args)
    end

    # Set attributes from encoded JSON object
    #
    # @param object [Hash] Decoded JSON object
    # @raise JSON::JSONError
    # @return self
    def load_json!(object)
      self.class.json_attrs.each do |sym, json_attr|
        self.instance_variable_set("@#{sym}", json_attr.load(object))
      end

      self
    end

    # Set attributes from encoded JSON object
    #
    # @param value [String] JSON-encoded object
    # @raise JSON::JSONError
    # @return self
    def from_json!(value)
      load_json! JSON.parse(value)
    end
  end
end
