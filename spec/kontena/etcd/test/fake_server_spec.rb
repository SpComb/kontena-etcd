require 'kontena/etcd/test/fake_server'

describe Kontena::Etcd::Test::FakeServer, :etcd => true do
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
        etcd.set('/kontena/test/quux', value: 'quux')

        expect(etcd.get('/kontena/test/quux').value).to eq 'quux'
      end

      it 'adds a new node to the parent directory' do
        etcd.set('/kontena/test/quux', value: 'quux')

        expect(etcd.get('/kontena/test/').children.map{|node| node.key }.sort).to eq [
          '/kontena/test/bar',
          '/kontena/test/foo',
          '/kontena/test/quux',
        ]
      end
    end

    describe '#delete' do
      it 'does not get a deleted node' do
        etcd.delete('/kontena/test/foo')
        expect{etcd.get('/kontena/test/foo')}.to raise_error(Etcd::KeyNotFound)
      end

      it 'does not list a deleted node' do
        etcd.delete('/kontena/test/foo')
        expect(etcd.get('/kontena/test').children.map{|node| node.key }.sort).to eq [
          '/kontena/test/bar',
        ]
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
end
