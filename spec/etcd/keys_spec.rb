require 'etcd/keys_helpers'

describe Etcd::Keys do
  let :cls do
    Class.new do
      include Etcd::Keys
    end
  end

  subject do
    cls.new
  end

  it 'returns nodes' do
    pools_kontena = instance_double(Etcd::Response,
      key: '/kontena/ipam/pools/kontena',
      value: '{"network": "kontena", "subnet": "10.81.0.0/16"}',
    )

    expect(subject).to receive(:get).with('/kontena/ipam/pools/').and_return(instance_double(Etcd::Response,
      children: [
        pools_kontena
      ],
    ))

    expect{|block| subject.each('/kontena/ipam/pools', &block) }.to yield_with_args('kontena', pools_kontena)
  end
end
