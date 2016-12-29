require 'kontena/etcd/test'

require 'webmock'

RSpec.shared_context 'etcd' do
  # etcd server for test
  let :etcd_server do
    if ENV['ETCD_ENDPOINT']
      Kontena::Etcd::Test::TestServer.new('/kontena')
    else
      Kontena::Etcd::Test::FakeServer.new('/kontena')
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

  # Do not run examples that are broken against the FakeServer
  config.filter_run_excluding :fake_etcd => false unless ENV['ETCD_ENDPOINT']
  config.filter_run_excluding :test_etcd => false if ENV['ETCD_ENDPOINT']

  # provide etcd and etcd_server for examples
  config.include_context 'etcd', :etcd => true

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
