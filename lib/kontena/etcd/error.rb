require 'kontena/json'
require 'json'

# /v2/keys API errors
# https://github.com/coreos/etcd/blob/v2.3.7/Documentation/errorcode.md
#
# Note that the cause JSON field conflicts with Exception#cause, and has been renamed to reason.
module Kontena::Etcd
  class Error < StandardError
    include Kontena::JSON::Model

    json_attr :error_code, name: 'errorCode'
    json_attr :index
    json_attr :message
    json_attr :reason, name: 'cause'

    class KeyNotFound < Error; end
    class TestFailed < Error; end
    class NotFile < Error; end
    class NotDir < Error; end
    class NodeExist < Error; end
    class RootROnly < Error; end
    class DirNotEmpty < Error; end

    class PrevValueRequired < Error; end
    class TTLNaN < Error; end
    class IndexNaN < Error; end
    class InvalidField < Error; end
    class InvalidForm < Error; end

    class RaftInternal < Error; end
    class LeaderElect < Error; end

    class WatcherCleared < Error; end
    class EventIndexCleared < Error; end

    ERRORS = {
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

    # @param status [Integer] HTTP response status
    # @param body [String] HTTP response body
    # @return [Kontena::Etcd::Error]
    def self.from_http(status, body)
      object = JSON.parse(body)

      cls = ERRORS[object['errorCode']] || Error
      cls.load_json object
    end

    def to_s
      return "#{@message}: #{@reason}"
    end
  end
end
