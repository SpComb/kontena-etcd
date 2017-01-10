require 'excon'

# Configurable etcd client, with logging
class Kontena::Etcd::Client
  include Kontena::Etcd::Logging

  DEFAULT_URI = URI('http://127.0.0.1:2379')

  attr_accessor :uri

  def self.from_env(env = ENV)
    if (endpoint = env['ETCD_ENDPOINT']) && !endpoint.empty?
      # we only support a single endpoint, which is a URL
      uri = URI(endpoint.split(',')[0])

      return new(uri)
    else
      return new()
    end
  end

  # @param uri [URI]
  def initialize(uri = DEFAULT_URI)
    @uri = uri
    @connection = Excon::Connection.new(
      scheme: uri.scheme,
      host: uri.host,
      hostname: uri.hostname,
      port: uri.port.to_i,
    )
  end

  def scheme
    @uri.scheme
  end
  def host
    @uri.host
  end
  def port
    @uri.port
  end

  # @param method [String] HTTP request method
  # @param path [String] Absolute HTTP path
  # @param query [Hash, nil] URL ?query parameters
  # @param form [Hash, nil] Body application/x-www-form-urlencoded parameters
  # @param expects [Array<Integer>] Expected HTTP response status
  # @param error_class [Class<Kontena::Etcd::Error>] class having #from_http method
  # @see Kontena::Etcd::Error::KeysError#from_http
  # @raise [error_class] decoded JSON error response per error_class.from_http(...)
  # @raise [Kontena::Etcd::Error::ClientError] unknown HTTP errors
  def http_request(method, path, query: nil, form: nil, expects: [200, 201], error_class: nil)
    headers = {}
    body = nil

    if form
      headers["Content-Type"] = "application/x-www-form-urlencoded"
      body = URI.encode_www_form(form)
    end

    return @connection.request(method: method, path: path, query: query,
      headers: headers,
      body: body,
      expects: expects,
    )
  rescue Excon::Error::HTTPStatus => error
    if error.response.headers['Content-Type'] == 'application/json' && error_class
      raise error_class.from_http(error.response.status, error.response.body)
    else
      # TODO: any details from the response body?
      raise Kontena::Etcd::Error::ClientError, error.response.reason_phrase
    end
  rescue Excon::Error => error
    raise Kontena::Etcd::Error::ClientError, error
  end

  # Query and parse the etcd daemon version
  #
  # @return [Hash{String => String}]
  def version
    @version ||= JSON.parse(self.http_request(:get, '/version').body)
  end

  include Kontena::Etcd::Keys
end
