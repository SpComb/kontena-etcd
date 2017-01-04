describe Kontena::Etcd do
  # Mocking node expiry only works against the fake etcd server
  it "Expires a node from etcd", :etcd => true, :etcd_fake => true do
    etcd.set('/kontena/test', 'test-value', ttl: 30)

    expect(etcd.get('/kontena/test')).to have_attributes(value: 'test-value')

    etcd_server.tick! 30

    expect{etcd.get('/kontena/test')}.to raise_error(Kontena::Etcd::Error::KeyNotFound)
  end

  it "Refreshes a node in etcd", :etcd => true, :etcd_fake => true do
    etcd.set('/kontena/test', 'test-value', ttl: 30)
    etcd_server.tick! 20

    etcd.refresh('/kontena/test', 30)
    etcd_server.tick! 20

    expect{etcd.get('/kontena/test')}.to_not raise_error
    etcd_server.tick! 10

    expect{etcd.get('/kontena/test')}.to raise_error(Kontena::Etcd::Error::KeyNotFound)
  end
end
