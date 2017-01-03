RSpec::Matchers.define_negated_matcher :not_output, :output

describe Kontena::Etcd::Keys do
  subject do
    Kontena::Etcd::Client.new
  end

  describe '#keys_path' do
    it "Normalizes path" do
      expect(subject.keys_path '').to eq '/v2/keys/'
      expect(subject.keys_path '/').to eq '/v2/keys/'
      expect(subject.keys_path '//').to eq '/v2/keys//' # TODO: normalize?

      expect(subject.keys_path 'test').to eq '/v2/keys/test'
      expect(subject.keys_path '/test').to eq '/v2/keys/test'
      expect(subject.keys_path '/test/').to eq '/v2/keys/test/'
    end
  end

  describe '#keys_request' do
    it 'raises unknown errors' do
      WebMock.stub_request(:get, 'http://127.0.0.1:2379/v2/keys/test').to_raise(Excon::Error::Timeout.new)

      expect{subject.keys_request(:get, '/test', method: 'GET')}.to raise_error(Excon::Error::Timeout)
    end

    it 'raises http errors' do
      WebMock.stub_request(:get, 'http://127.0.0.1:2379/v2/keys/test').to_return(
        status: 503,
        body: "etcd is broken"
      )

      expect{subject.keys_request(:get, '/test', method: 'GET')}.to raise_error(Excon::Error::HTTPStatus)
    end

    it 'raises etcd errors' do
      WebMock.stub_request(:get, 'http://127.0.0.1:2379/v2/keys/test').to_return(
        status: 404,
        headers: { 'Content-Type' => 'application/json' },
        body: {'errorCode' => 100, 'index' => 4, 'cause' => '/test', 'message' => "Key not found"}.to_json,
      )

      expect{subject.keys_request(:get, '/test', method: 'GET')}.to raise_error(Kontena::Etcd::Error::KeyNotFound) { |error|
        aggregate_failures do
          expect(error).to be_a Kontena::Etcd::Error
          expect(error).to be_a Kontena::Etcd::Error::KeyNotFound

          expect(error.error_code).to eq 100
          expect(error.index).to eq 4
          expect(error.reason).to eq '/test'
          expect(error.message).to eq "Key not found"

          expect(error.to_s).to eq "Key not found: /test"
          expect(error.cause).to be_a Excon::Error::HTTPStatus
        end
      }
    end

    it 'returns a response node' do
      WebMock.stub_request(:get, 'http://127.0.0.1:2379/v2/keys/test').to_return(
        status: 200,
        headers: {
          'Content-Type' => 'application/json',
          'X-Etcd-Index' => '1',
          'X-Raft-Index' => '2',
          'X-Raft-Term' => '3',
        },
        body: {"action" => "get", "node" => {"key" => "/test", "modifiedIndex" => 3, "value" => "test"}}.to_json,
      )

      response = subject.keys_request(:get, '/test', method: 'GET')

      expect(response).to be_a Kontena::Etcd::Keys::Response
      expect(response.action).to eq 'get'
      expect(response.node.key).to eq '/test'
      expect(response.node.modified_index).to eq 3
      expect(response.node.value).to eq 'test'
    end

    context 'with debug logging' do
      before do
        subject.logger.level = Logger::DEBUG
      end

      it 'logs requests for a node' do
        WebMock.stub_request(:get, 'http://127.0.0.1:2379/v2/keys/test').to_return(
          status: 200,
          headers: {
            'Content-Type' => 'application/json',
            'X-Etcd-Index' => '1',
            'X-Raft-Index' => '2',
            'X-Raft-Term' => '3',
          },
          body: {"action" => "get", "node" => {"key" => "/test", "modifiedIndex" => 3, "value" => "test"}}.to_json,
        )

        expect{subject.logger.reopen($stderr); subject.keys_request(:get, '/test', method: 'GET')}.to output(/DEBUG -- Kontena::Etcd::Client: get \/test : get \/test@3: test/).to_stderr
      end

      it 'logs requests for a directory' do
        WebMock.stub_request(:get, 'http://127.0.0.1:2379/v2/keys/test').to_return(
          status: 200,
          headers: {
            'Content-Type' => 'application/json',
            'X-Etcd-Index' => '1',
            'X-Raft-Index' => '2',
            'X-Raft-Term' => '3',
          },
          body: {'action' => 'get', 'node' => { 'key' => "/test", 'dir' => true, "modifiedIndex": 3, 'nodes' => [
            { 'key' => "/test/bar", 'value' => 'bar' },
            { 'key' => "/test/foo", 'value' => 'foo' },
            { 'key' => "/test/subdir", 'dir' => true, 'nodes' => [ ] },
          ]}}.to_json,
        )

        expect{subject.logger.reopen($stderr); subject.keys_request(:get, '/test', method: 'GET')}.to output(/DEBUG -- Kontena::Etcd::Client: get \/test : get \/test\/@3: bar foo subdir\//).to_stderr
      end

      it 'logs errors' do
        WebMock.stub_request(:get, 'http://127.0.0.1:2379/v2/keys/test').to_return(
          status: 404,
          headers: { 'Content-Type' => 'application/json' },
          body: {'errorCode' => 100, 'index' => 4, 'cause' => '/test', 'message' => "Key not found"}.to_json,
        )

        expect{subject.logger.reopen($stderr); subject.keys_request(:get, '/test', method: 'GET')}.to raise_error(Kontena::Etcd::Error::KeyNotFound).and output(/DEBUG -- Kontena::Etcd::Client: get \/test : error Kontena::Etcd::Error::KeyNotFound \/test@4: Key not found/).to_stderr
      end
    end

    context 'with info logging' do
      before do
        subject.logger.level = Logger::INFO
      end

      it 'does not log responses' do
        WebMock.stub_request(:get, 'http://127.0.0.1:2379/v2/keys/test').to_return(
          status: 200,
          headers: {
            'Content-Type' => 'application/json',
            'X-Etcd-Index' => '1',
            'X-Raft-Index' => '2',
            'X-Raft-Term' => '3',
          },
          body: {"action" => "get", "node" => {"key" => "/test", "modifiedIndex" => 3, "value" => "test"}}.to_json,
        )

        expect{subject.logger.reopen($stderr); subject.keys_request(:get, '/test', method: 'GET')}.to_not output.to_stderr
      end

      it 'does not log errors' do
        WebMock.stub_request(:get, 'http://127.0.0.1:2379/v2/keys/test').to_return(
          status: 404,
          headers: { 'Content-Type' => 'application/json' },
          body: {'errorCode' => 100, 'index' => 4, 'cause' => '/test', 'message' => "Key not found"}.to_json,
        )

        expect{subject.logger.reopen($stderr); subject.keys_request(:get, '/test', method: 'GET')}.to raise_error(Kontena::Etcd::Error::KeyNotFound).and not_output.to_stderr
      end
    end
  end

  describe '#each' do
    it 'yields nodes' do
      WebMock.stub_request(:get, 'http://127.0.0.1:2379/v2/keys/test/').to_return(
        status: 200,
        headers: {
          'Content-Type' => 'application/json',
          'X-Etcd-Index' => '1',
          'X-Raft-Index' => '2',
          'X-Raft-Term' => '3',
        },
        body: {'action' => 'get', 'node' => { 'key' => "/test", 'dir' => true, "modifiedIndex": 3, 'nodes' => [
          { 'key' => "/test/bar", 'value' => 'bar' },
          { 'key' => "/test/foo", 'value' => 'foo' },
          { 'key' => "/test/quux", 'dir' => true },
        ]}}.to_json,
      )

      expect{|block| subject.each('/test', &block) }.to yield_successive_args(
        ['bar', Kontena::Etcd::Node],
        ['foo', Kontena::Etcd::Node],
        ['quux', Kontena::Etcd::Node],
      )
    end
  end
end