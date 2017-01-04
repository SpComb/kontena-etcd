require_relative '../../examples/kontena-etcd-model'

describe Example do
  it "Reads a node from etcd", :etcd => true do
    etcd_server.load!(
      '/kontena/example/foo1' => {'bar' => 'bar2'},
    )

    expect(described_class.get('foo1').bar).to eq 'bar2'

    expect(etcd_server).to_not be_modified
  end

  it "Writes itself to etcd", :etcd => true do
    described_class.create('foo1', bar: 'bar2')

    expect(etcd_server).to be_modified
    expect(etcd_server.logs).to eq [
      [:create, '/kontena/example/foo1'],
    ]
    expect(etcd_server.list).to eq Set.new([
      '/kontena/',
      '/kontena/example/',
      '/kontena/example/foo1',
    ])
    expect(etcd_server.nodes).to eq(
      '/kontena/example/foo1' => {'bar' => 'bar2'},
    )
  end
end
