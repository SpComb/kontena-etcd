class Etcd::Node
  # Walk recursive nodes
  #
  # @yield [node]
  # @yieldparam node [Etcd::Node]
  def walk(&block)
    if directory?
      children.each do |node|
        node.walk(&block)
      end
    else
      yield self
    end
  end
end
