require 'kontena/json'

class Kontena::Etcd::Node
  include Kontena::JSON::Model

  json_attr :key
  json_attr :value
  json_attr :modified_index, name: "modifiedIndex"
  json_attr :created_index, name: "createdIndex"
  json_attr :expiration
  json_attr :ttl
  json_attr :dir
  json_attr :nodes, array_model: Kontena::Etcd::Node

  # @raise [RuntimeError] this node is not a directory
  # @return [Array<Kontena::Etcd::Node>] directory nodes
  def nodes
    raise "Node is not a directory" unless @dir

    # etcd omits the nodes for an empty directory
    @nodes || []
  end

  alias_method :children, :nodes
  alias_method :directory?, :dir

  # Walk recursive leaf nodes
  #
  # @yield [node]
  # @yieldparam node [Kontena::Etcd::Node]
  def walk(&block)
    if directory?
      nodes.each do |node|
        node.walk(&block)
      end
    else
      yield self
    end
  end
end
