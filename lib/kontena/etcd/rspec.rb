require 'kontena/etcd/client'
require 'kontena/etcd/test'

RSpec.shared_context 'etcd', etcd: true do
  # etcd server for test
  let :etcd_server do
    if ENV['ETCD_ENDPOINT']
      Kontena::Etcd::Test::TestServer.new('/kontena/ipam')
    else
      Kontena::Etcd::Test::FakeServer.new('/kontena/ipam')
    end
  end

  # etcd client for test
  let :etcd do
    Kontena::Etcd::Client.new
  end
end

RSpec.configure do |config|
  # kill etcd queries for non-etcd examples
  config.before :each do
    Kontena::Etcd::Model.etcd = instance_double(Kontena::Etcd::Client)
  end

  config.before :each, etcd: true do
    if etcd_endpoint = ENV['ETCD_ENDPOINT']
      uri = URI(etcd_endpoint)

      WebMock.disable_net_connect!(allow: "#{uri.host}:#{uri.port}")
    else
      WebMock.stub_request(:any, /localhost:2379/).to_rack(etcd_server.api)
    end

    # clear etcd database
    etcd_server.reset!

    Kontena::Etcd::Model.etcd = etcd
  end

end

# Workaround https://github.com/ranjib/etcd-ruby/issues/59
class RSpec::Core::Formatters::ExceptionPresenter
  def final_exception(exception, previous=[])
    cause = exception.cause
    if cause && !previous.include?(cause) && !cause.is_a?(String)
      previous << cause
      final_exception(cause, previous)
    else
      exception
    end
  end
end
