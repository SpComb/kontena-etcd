describe Kontena::Etcd::Test::TestServer, :etcd => true do
  describe '#logs' do
    it "is empty if the root is empty " do
      expect{etcd.get('/kontena')}.to raise_error(Kontena::Etcd::Error::KeyNotFound)

      expect(etcd_server.logs).to be_empty
    end

    it "is false if unmodified " do
      etcd_server.load!(
        '/kontena/test' => 'test',
      )

      expect(etcd_server.logs).to be_empty
    end

    it "is true if modified " do
      etcd_server.load!(
        '/kontena/test' => "test",
      )

      etcd.set('/kontena/test', "test 2")

      expect(etcd_server.logs).to eq [
        [:set, '/kontena/test'],
      ]
    end

    it "Does not trip modified?" do
      etcd_server.load!(
        '/kontena/test' => 'test',
      )

      expect(etcd_server.logs).to be_empty
      expect(etcd_server).to_not be_modified
    end
  end
end
