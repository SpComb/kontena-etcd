describe Kontena::Etcd::Client do
  describe '#from_env' do
    it 'fails on an invalid URL missing the schema' do
      expect{described_class.from_env('ETCD_ENDPOINT' => '172.16.0.1:4001')}.to raise_error(URI::InvalidURIError)
    end

    it 'skips an empty ETCD_ENDPOINT=' do
      subject = described_class.from_env('ETCD_ENDPOINT' => '')

      expect(subject.uri).to eq Kontena::Etcd::Client::DEFAULT_URI
    end

    it 'parses ETCD_ENDPOINT=http://172.16.0.1:4001' do
      subject = described_class.from_env('ETCD_ENDPOINT' => 'http://172.16.0.1:4001')

      expect(subject.scheme).to eq 'http'
      expect(subject.host).to eq '172.16.0.1'
      expect(subject.port).to eq 4001
    end

    it 'parses ETCD_ENDPOINT=http://172.16.0.1' do
      subject = described_class.from_env('ETCD_ENDPOINT' => 'http://172.16.0.1')

      expect(subject.scheme).to eq 'http'
      expect(subject.host).to eq '172.16.0.1'
      expect(subject.port).to eq 80 # XXX:
    end

    it 'uses the configuration' do
      subject = described_class.from_env(env = {})

      expect(subject.scheme).to eq 'http'
      expect(subject.host).to eq '127.0.0.1'
      expect(subject.port).to eq 2379
    end
  end

  context "for the default configuration" do
    subject do
      described_class.new()
    end

    let :version do
      {"etcdserver"=>"2.3.3", "etcdcluster"=>"2.3.0"}
    end


    it "requests the version" do
      WebMock.stub_request(:get, 'http://127.0.0.1:2379/version')
        .and_return(
          headers: { 'Content-Type' => 'application/json' },
          body: version.to_json,
        )

      expect(subject.version).to eq version
    end
  end
end
