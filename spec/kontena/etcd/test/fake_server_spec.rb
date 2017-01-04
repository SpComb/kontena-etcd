require 'kontena/etcd/test'

describe Kontena::Etcd::Test::FakeServer do
  let :etcd_server do
    Kontena::Etcd::Test::FakeServer.new('/kontena')
  end

  let :etcd do
    Kontena::Etcd::Client.new
  end

  before :each do
    WebMock.stub_request(:any, /127.0.0.1:2379/).to_rack(etcd_server.api)

    # clear etcd database
    etcd_server.reset!

    Kontena::Etcd::Model.etcd = etcd
  end

  context 'for a simple tree' do
    before do
      etcd_server.load!(
        '/kontena/test/foo' => 'foo',
        '/kontena/test/bar' => 'bar',
      )
    end

    describe '#list' do
      it 'returns the initially loaded keys' do
        expect(etcd_server.list).to eq [
          '/kontena/',
          '/kontena/test/',
          '/kontena/test/bar',
          '/kontena/test/foo',
        ].to_set
      end
    end

    describe '#get' do
      it 'gets a node' do
          expect(etcd.get('/kontena/test/foo').value).to eq 'foo'
          expect(etcd.get('/kontena/test/bar').value).to eq 'bar'
      end

      it 'gets a directory' do
        expect(etcd.get('/kontena/test').directory?).to be true
        expect(etcd.get('/kontena/test').children.map{|node| node.key }.sort).to eq [
          '/kontena/test/bar',
          '/kontena/test/foo',
        ]
      end
    end

    describe '#set' do
      it 'creates a new node' do
        etcd.set('/kontena/test/quux', 'quux')

        expect(etcd.get('/kontena/test/quux').value).to eq 'quux'
      end

      it 'adds a new node to the parent directory' do
        etcd.set('/kontena/test/quux', 'quux')

        expect(etcd.get('/kontena/test/').children.map{|node| node.key }.sort).to eq [
          '/kontena/test/bar',
          '/kontena/test/foo',
          '/kontena/test/quux',
        ]
      end

      it 'returns an error when using prevIndex for a non-existant node' do
        expect{etcd.set('/kontena/test/quux', 'quux', prevIndex: 1)}.to raise_error(Kontena::Etcd::Error::KeyNotFound)
      end

      it 'logs a compareAndSwap event when using prevValue with the correct value' do
        response = etcd.set('/kontena/test/foo', 'foo2', prevValue: 'foo')

        expect(response.action).to eq 'compareAndSwap'
        expect(etcd_server.nodes).to eq(
          '/kontena/test/foo' => 'foo2',
          '/kontena/test/bar' => 'bar',
        )
        expect(etcd_server.logs).to eq [
          [:compareAndSwap, '/kontena/test/foo']
        ]
      end

      it 'returns an error when using prevValue with the wrong value' do
        expect{etcd.set('/kontena/test/foo', 'foo', prevValue: 'foo2')}.to raise_error(Kontena::Etcd::Error::TestFailed)
      end

      it 'logs a compareAndSwap event when using prevIndex with the correct index' do
        response = etcd.set('/kontena/test/foo', 'foo2', prevIndex: 1)

        expect(response.action).to eq 'compareAndSwap'
        expect(etcd_server.nodes).to eq(
          '/kontena/test/foo' => 'foo2',
          '/kontena/test/bar' => 'bar',
        )
        expect(etcd_server.logs).to eq [
          [:compareAndSwap, '/kontena/test/foo']
        ]
      end

      it 'returns an error when using prevIndex with the wrong index' do
        expect{etcd.set('/kontena/test/foo', 'foo', prevIndex: 2)}.to raise_error(Kontena::Etcd::Error::TestFailed)
      end
    end

    describe '#delete' do
      it 'does not get a deleted node' do
        etcd.delete('/kontena/test/foo')
        expect{etcd.get('/kontena/test/foo')}.to raise_error(Kontena::Etcd::Error::KeyNotFound)
      end

      it 'does not list a deleted node' do
        etcd.delete('/kontena/test/foo')
        expect(etcd.get('/kontena/test').children.map{|node| node.key }.sort).to eq [
          '/kontena/test/bar',
        ]
      end

      it 'deletes a node with prevValue' do
        expect{etcd.delete('/kontena/test/foo', prevValue: 'foo')}.to_not raise_error

        expect(etcd_server.nodes).to eq(
          '/kontena/test/bar' => 'bar',
        )
        expect(etcd_server.logs).to eq [[:compareAndDelete, '/kontena/test/foo']]
      end

      it 'raises with a mismatching prevValue' do
        expect{etcd.delete('/kontena/test/foo', prevValue: 'bar')}.to raise_error(Kontena::Etcd::Error::TestFailed) { |error|
          expect(error.to_s).to eq "Compare failed: [bar != foo]"
        }

        expect(etcd_server.nodes).to eq(
          '/kontena/test/foo' => 'foo',
          '/kontena/test/bar' => 'bar',
        )
        expect(etcd_server.logs).to eq []
      end

      it 'deletes a node with prevIndex' do
        expect{etcd.delete('/kontena/test/foo', prevIndex: 1)}.to_not raise_error

        expect(etcd_server.nodes).to eq(
          '/kontena/test/bar' => 'bar',
        )
        expect(etcd_server.logs).to eq [[:compareAndDelete, '/kontena/test/foo']]
      end

      it 'raises with a mismatching prevValue' do
        expect{etcd.delete('/kontena/test/foo', prevIndex: 3)}.to raise_error(Kontena::Etcd::Error::TestFailed) { |error|
          expect(error.to_s).to eq "Compare failed: [3 != 1]"
        }

        expect(etcd_server.nodes).to eq(
          '/kontena/test/foo' => 'foo',
          '/kontena/test/bar' => 'bar',
        )
        expect(etcd_server.logs).to eq []
      end
    end
  end

  context "for a nested tree" do
    before do
      etcd_server.load!(
        '/kontena/test/test1/children/childA' => { 'field' => "value 1A" },
        '/kontena/test/test1/children/childB' => { 'field' => "value 1B" },
        '/kontena/test/test2/children/childA' => { 'field' => "value 2A" },
        '/kontena/test/test2/children/childB' => { 'field' => "value 2B" },
      )
    end

    it "lists the nodes" do
      expect(etcd.get('/kontena/test/').children.map{|node| node.key }.sort).to eq [
        '/kontena/test/test1',
        '/kontena/test/test2',
      ]
    end
  end

  describe '#set' do
    it 'logs a create event when using prevExist=false' do
      etcd.set('/kontena/test/quux', '{"quux": false}', prevExist: false)

      expect(etcd_server.nodes).to eq(
        '/kontena/test/quux' => { 'quux' => false },
      )
      expect(etcd_server.logs).to eq [[:create, '/kontena/test/quux']]
    end

    it 'logs a set event when not using prevExist' do
      etcd.set('/kontena/test/quux', '{"quux": true}')

      expect(etcd_server.nodes).to eq(
        '/kontena/test/quux' => { 'quux' => true },
      )
      expect(etcd_server.logs).to eq [[:set, '/kontena/test/quux']]
    end

    it 'refreshes a node' do
      etcd.set('/kontena/test/quux', '{"quux": true}', ttl: 30)
      etcd.refresh('/kontena/test/quux', 60)

      expect(etcd_server.nodes).to eq(
        '/kontena/test/quux' => { 'quux' => true },
      )
      expect(etcd_server.logs).to eq [[:set, '/kontena/test/quux']]
    end
  end

  describe '#tick' do
    it "returns a TTL for a node" do
      etcd.set('/kontena/test/quux', 'quux', ttl: 30)

      expect(etcd.get('/kontena/test/quux').node.ttl).to eq 30
    end

    it "ticks the TTL for a node" do
      etcd.set('/kontena/test/quux', 'quux', ttl: 30)

      etcd_server.tick! 10

      expect(etcd.get('/kontena/test/quux').node.ttl).to eq 20
    end

    it "expires a node" do
      etcd.set('/kontena/test/quux', 'quux', ttl: 30)

      etcd_server.tick! 30

      expect{etcd.get('/kontena/test/quux')}.to raise_error(Kontena::Etcd::Error::KeyNotFound)

      expect(etcd_server.nodes).to eq({})
      expect(etcd_server.logs).to eq [
        [:set, '/kontena/test/quux'],
        [:expire, '/kontena/test/quux'],
      ]
    end

    it "does not expires a node with a longer TTL" do
      etcd.set('/kontena/test/quux', 'quux', ttl: 30)

      etcd_server.tick! 15

      expect{etcd.get('/kontena/test/quux')}.to_not raise_error

      expect(etcd_server.nodes).to eq(
        '/kontena/test/quux' => 'quux',
      )
      expect(etcd_server.logs).to eq [
        [:set, '/kontena/test/quux'],
      ]
    end

    it "does not expires a node without any ttl" do
      etcd.set('/kontena/test/quux', 'quux')

      etcd_server.tick! 15

      expect{etcd.get('/kontena/test/quux')}.to_not raise_error

      expect(etcd_server.nodes).to eq(
        '/kontena/test/quux' => 'quux',
      )
      expect(etcd_server.logs).to eq [
        [:set, '/kontena/test/quux'],
      ]
    end
  end
end
