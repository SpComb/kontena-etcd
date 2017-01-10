require 'kontena/json'
require 'json'

# /v2/keys API errors
# https://github.com/coreos/etcd/blob/v2.3.7/Documentation/errorcode.md
#
# Note that the cause JSON field conflicts with Exception#cause, and has been renamed to reason.
module Kontena::Etcd
  class Error < StandardError
    class ClientError < Error

    end

    # /v2/keys HTTP error response
    class KeysError < Error
      include Kontena::JSON::Model

      # @param status [Integer] HTTP response status
      # @param body [String] HTTP response body
      # @return [Kontena::Etcd::Error]
      def self.from_http(status, body)
        object = JSON.parse(body)

        cls = KEYS_ERRORS[object['errorCode']] || Error
        cls.load_json object
      end

      json_attr :error_code, name: 'errorCode'
      json_attr :index
      json_attr :message
      json_attr :reason, name: 'cause'

      def to_s
        return "#{@message}: #{@reason}"
      end
    end

    class KeyNotFound < KeysError; end # HTTP 404
    class TestFailed < KeysError; end
    class NotFile < KeysError; end
    class NotDir < KeysError; end
    class NodeExist < KeysError; end
    class RootROnly < KeysError; end
    class DirNotEmpty < KeysError; end

    class PrevValueRequired < KeysError; end
    class TTLNaN < KeysError; end
    class IndexNaN < KeysError; end
    class InvalidField < KeysError; end
    class InvalidForm < KeysError; end

    class RaftInternal < KeysError; end # HTTP 500
    class LeaderElect < KeysError; end

    class WatcherCleared < KeysError; end
    class EventIndexCleared < KeysError; end

    KEYS_ERRORS = {
      100 => KeyNotFound,
      101 => TestFailed,
      102 => NotFile,
      104 => NotDir,
      105 => NodeExist,
      107 => RootROnly,
      108 => DirNotEmpty,

      201 => PrevValueRequired,
      202 => TTLNaN,
      203 => IndexNaN,
      209 => InvalidField,
      210 => InvalidForm,

      300 => RaftInternal,
      301 => LeaderElect,

      400 => WatcherCleared,
      401 => EventIndexCleared,
    }

  end
end
