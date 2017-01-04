require 'kontena/etcd'

class Example
  include Kontena::JSON::Model
  include Kontena::Etcd::Model

  etcd_path '/kontena/example/:foo'
  json_attr :bar
end
