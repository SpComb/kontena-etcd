# `Kontena::Etcd`
A Ruby client for [`etcd`](https://github.com/coreos/etcd) with JSON Model mapper, recursive Reader/Writer, rspec testing support.

## Features
Inspired by and mostly compatible with https://github.com/ranjib/etcd-ruby, extended with additional features:

### Request DEBUG Logging

Use the `LOG_LEVEL=debug` env to log all `Kontena::Etcd::Client` requests:

```
D, [2017-01-03T16:03:33.088421 #5247] DEBUG -- Kontena::Etcd::Client: get /kontena/test/foo {}: error Kontena::Etcd::Error::KeyNotFound /kontena/test/foo@0: Key not found
D, [2017-01-03T16:03:33.107597 #5247] DEBUG -- Kontena::Etcd::Client: get /kontena/test/ {}: get /kontena/test/@1: test1/ test2/
D, [2017-01-03T16:03:33.127267 #5247] DEBUG -- Kontena::Etcd::Client: set /kontena/test/quux {:prevExist=>false, :value=>"{\"quux\": false}"}: create /kontena/test/quux@1: {"quux": false}
D, [2017-01-03T16:03:33.425220 #5247] DEBUG -- Kontena::Etcd::Client: watch /kontena {:wait=>true, :recursive=>true, :waitIndex=>1799, :timeout=>1.0}: set /kontena/test1@1799: {"test":1}
D, [2017-01-03T16:03:33.428694 #5247] DEBUG -- Kontena::Etcd::Client: watch /kontena {:wait=>true, :recursive=>true, :waitIndex=>1800, :timeout=>1.0}: delete /kontena/test1@1800:
```

### Client configuration from `ETCD_ENDPOINT=http://127.0.0.1:2379`

Use `Kontena::Etcd::Client.from_env` to automatically configure the client from the `ETCD_ENDPOINT` environment variable.

### `etcd` version 2.3 [`/v2/keys` API](https://github.com/coreos/etcd/blob/v2.3.7/Documentation/api.md#key-space-operations)

* `get`
* `set`
* [`refresh`](https://github.com/coreos/etcd/blob/v2.3.7/Documentation/api.md#refreshing-key-ttl)
* `delete`
* `post`
* `watch`

### `Kontena::Etcd::Reader`

Atomically follow a key prefix, synchronizing the initial etcd nodes using a recursive get, and then applying recursive watch events to
maintain the etcd nodes.

```ruby
#!/usr/bin/env ruby

require 'kontena/etcd'

reader = Kontena::Etcd::Reader.new('/kontena')

reader.run do |nodes|
  puts nodes.map{|node| "#{node.key}=#{node.value}"}.join ' '
end
```

Gives the following output:

```
I, [2017-01-03T16:12:40.865194 #6058]  INFO -- Kontena::Etcd::Reader: set /kontena/test1: {"key":"/kontena/test1","value":"test1","modifiedIndex":1812,"createdIndex":1812,"expiration":null,"ttl":null,"dir":null,"nodes":null}
/kontena/test1=test1
I, [2017-01-03T16:12:44.942192 #6058]  INFO -- Kontena::Etcd::Reader: set /kontena/test2: {"key":"/kontena/test2","value":"test2","modifiedIndex":1813,"createdIndex":1813,"expiration":null,"ttl":null,"dir":null,"nodes":null}
/kontena/test1=test1 /kontena/test2=test2
I, [2017-01-03T16:12:48.289306 #6058]  INFO -- Kontena::Etcd::Reader: set /kontena/test1: {"key":"/kontena/test1","value":"test1-v2","modifiedIndex":1814,"createdIndex":1814,"expiration":null,"ttl":null,"dir":null,"nodes":null}
/kontena/test1=test1-v2 /kontena/test2=test2
I, [2017-01-03T16:12:52.488216 #6058]  INFO -- Kontena::Etcd::Reader: delete /kontena/test2: {"key":"/kontena/test2","value":null,"modifiedIndex":1815,"createdIndex":1813,"expiration":null,"ttl":null,"dir":null,"nodes":null}
/kontena/test1=test1-v2
I, [2017-01-03T16:13:14.723846 #6058]  INFO -- Kontena::Etcd::Reader: set /kontena/test2: {"key":"/kontena/test2","value":"test2-expiring","modifiedIndex":1816,"createdIndex":1816,"expiration":"2017-01-03T14:13:24.721135508Z","ttl":10,"dir":null,"nodes":null}
/kontena/test1=test1-v2 /kontena/test2=test2-expiring
I, [2017-01-03T16:13:25.178353 #6058]  INFO -- Kontena::Etcd::Reader: expire /kontena/test2: {"key":"/kontena/test2","value":null,"modifiedIndex":1817,"createdIndex":1816,"expiration":null,"ttl":null,"dir":null,"nodes":null}
/kontena/test1=test1-v2
```

### `Kontena::Etcd::Writer`

Maintain a set of nodes in etcd, automatically adding and removing nodes when updated.

Supports TTL for automatic expiry on writer crashes, with periodic refreshing to maintain the nodes.
The refresh operation also serves to detect any write conflicts.

### `Kontena::Etcd::Model`

Map Ruby objects from JSON objects in etcd using class mixins/definitions:

```ruby
class Example
  include Kontena::JSON::Model
  include Kontena::Etcd::Model

  etcd_path '/kontena/example/:foo'
  json_attr :bar
end
```

Allows operations such as the following:

```ruby
Example.delete

Example.create('foo1', bar: 'bar2')

Example.each do |example|
  puts "#{example.foo}=#{example.bar}"
end

example = Example.get('foo1')
```

With resulting output:

```
D, [2017-01-04T13:22:02.004864 #7431] DEBUG -- Kontena::Etcd::Client: delete /kontena/example/ {:recursive=>true}: delete /kontena/example/@1450:
D, [2017-01-04T13:22:02.011548 #7431] DEBUG -- Kontena::Etcd::Client: set /kontena/example/foo1 {:prevExist=>false, :value=>"{\"bar\":\"bar2\"}"}: create /kontena/example/foo1@1451: {"bar":"bar2"}
D, [2017-01-04T13:22:02.012594 #7431] DEBUG -- Kontena::Etcd::Client: get /kontena/example/ {}: get /kontena/example/@1451: foo1
foo1=bar2
D, [2017-01-04T13:22:02.013462 #7431] DEBUG -- Kontena::Etcd::Client: get /kontena/example/foo1 {}: get /kontena/example/foo1@1451: {"bar":"bar2"}
```

## Testing
Includes [RSpec](http://rspec.info/) support for writing tests against etcd, allowing specs to expect on the resulting etcd modifications.

Tests can be run using either an internal fake `etcd` API implementation, or a real `etcd` server.
The fake `etcd` server collects a log of any operations that modify the fake etcd store.
When running against a real `etcd` server, the `modified?` and `logs` helpers use the `X-Etcd-Index` and recursive watches to find any operations performed by the example.

```ruby
require 'rspec'
require 'kontena/etcd/rspec'

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
```

When running against the fake `etcd` server, additional behavior such as TTL expiration can be tested:

```ruby
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
```

### Issues

* The tests are currently hardcoded to assume a `/kontena` prefix for all keys
