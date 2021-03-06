describe Kontena::Etcd::Model do
  describe Kontena::Etcd::Model::Schema do
    it 'rejects a non-absolute path' do
      expect{described_class.new('test')}.to raise_error ArgumentError
    end

    it 'rejects a directory path' do
      expect{described_class.new('/kontena/test/:name/')}.to raise_error ArgumentError
    end

    it 'parses a simple path' do
      expect(described_class.new('/kontena/test/:name').path).to eq ['kontena', 'test', :name]
    end

    it 'parses a simple path with a sub-node' do
      expect(described_class.new('/kontena/test/:name/foo').path).to eq ['kontena', 'test', :name, 'foo']
    end

    it 'parses a complex path with two symbols' do
      expect(described_class.new('/kontena/test/:name/foo/:bar').path).to eq ['kontena', 'test', :name, 'foo', :bar]
    end

    context 'for a simple schema' do
      let :subject do
        described_class.new('/kontena/test/:name')
      end

      it 'renders the path for the class' do
        expect(subject.to_s).to eq '/kontena/test/:name'
      end

      it 'renders the path prefix for the class' do
        expect(subject.prefix()).to eq '/kontena/test/'
      end

      it 'renders the complete path prefix for the class' do
        expect(subject.prefix('test1')).to eq '/kontena/test/test1'
      end

      it 'fails the prefix if given too many arguments' do
        expect{subject.prefix('test1', 'test2')}.to raise_error ArgumentError
      end
    end
  end

  it "raises if including in the wrong order" do
    expect{
      Class.new do
        include Kontena::Etcd::Model
        include Kontena::JSON::Model
      end
    }.to raise_error(TypeError)
  end

  context 'a simple model' do
    class TestEtcd
      include Kontena::JSON::Model
      include Kontena::Etcd::Model

      etcd_path '/kontena/test/:name'
      json_attr :field, type: String
    end

    it 'initializes the etcd key instance variables' do
      expect{TestEtcd.new()}.to raise_error ArgumentError, "Missing key argument for :name"
      expect(TestEtcd.new('test').name).to eq 'test'
      expect{TestEtcd.new('test', 'extra')}.to raise_error ArgumentError, "Extra key arguments"
    end

    it 'initializes the JSON attribute instance variables' do
      expect(TestEtcd.new('test').field).to eq nil
      expect(TestEtcd.new('test', field: "value").field).to eq "value"
      expect{TestEtcd.new('test', notfield: false)}.to raise_error ArgumentError, "Extra JSON attr argument: :notfield"
    end

    it 'initializes the object with etcd key and JSON attrribute instance variables' do
      expect(TestEtcd.new('test', field: "value").name).to eq 'test'
    end

    it 'renders to path for the object' do
      expect(TestEtcd.new('test1').etcd_key).to eq '/kontena/test/test1'
    end

    context 'with only key values' do
      it 'compares the key' do
        expect(TestEtcd.new('test1') <=> TestEtcd.new('test2')).to eq(-1)
        expect(TestEtcd.new('test1') <=> TestEtcd.new('test1')).to eq(0)
        expect(TestEtcd.new('test2') <=> TestEtcd.new('test1')).to eq(1)
      end

      it 'sorts before values' do
        expect(TestEtcd.new('test1') <=> TestEtcd.new('test1', field: "value 1")).to eq(-1)
      end
    end

    context 'with key and attr values' do
      it 'compares the keys' do
        expect(TestEtcd.new('test1', field: "value") <=> TestEtcd.new('test2', field: "value")).to eq(-1)
        expect(TestEtcd.new('test1', field: "value") <=> TestEtcd.new('test1', field: "value")).to eq(0)
        expect(TestEtcd.new('test2', field: "value") <=> TestEtcd.new('test1', field: "value")).to eq(+1)
      end

      it 'compares the values with matching keys' do
        expect(TestEtcd.new('test1', field: "value 1") <=> TestEtcd.new('test1', field: "value 2")).to eq(-1)
        expect(TestEtcd.new('test1', field: "value 1") <=> TestEtcd.new('test1', field: "value 1")).to eq(0)
        expect(TestEtcd.new('test1', field: "value 2") <=> TestEtcd.new('test1', field: "value 1")).to eq(+1)
      end

      it 'sorts after missing values' do
        expect(TestEtcd.new('test1', field: "value") <=> TestEtcd.new('test1')).to eq(+1)
      end
    end

    describe '#mkdir' do
      it 'creates directory in etcd', :etcd => true do
        expect(etcd).to receive(:set).with('/kontena/test/', dir: true, prevExist: false).and_call_original

        TestEtcd.mkdir()

        expect(etcd_server).to be_modified
        expect(etcd_server.logs).to eq [
          [:create, '/kontena/test/'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/',
          '/kontena/test/',
        ])
      end

      it 'skips existing directories', :etcd => true do
        etcd_server.load!(
          '/kontena/test/' => nil,
        )

        expect(etcd).to receive(:set).with('/kontena/test/', dir: true, prevExist: false).and_call_original

        TestEtcd.mkdir()

        expect(etcd_server).to_not be_modified
      end

      it 'fails if given a full key', :etcd => true do
        expect{TestEtcd.mkdir('test')}.to raise_error(ArgumentError)

        expect(etcd_server).to_not be_modified
      end
    end

    describe '#get' do
      it 'rejects an empty key' do
        expect{ TestEtcd.get('') }.to raise_error(ArgumentError)
      end

      it 'returns nil if missing from etcd', :etcd => true do
        expect(etcd).to receive(:get).with('/kontena/test/test1').and_call_original

        expect(TestEtcd.get('test1')).to be_nil

        expect(etcd_server).to_not be_modified
        expect(etcd_server.list).to be_empty
      end

      it 'returns object loaded from etcd', :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1' => { 'field' => "value" }
        )
        expect(etcd).to receive(:get).with('/kontena/test/test1').and_call_original

        subject = TestEtcd.get('test1')

        expect(subject).to eq TestEtcd.new('test1', field: "value")
        expect(subject.etcd_index).to be >= etcd_server.start_index

        expect(etcd_server).to_not be_modified
      end

      it 'raises Invalid if the etcd node is a directory', :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1/' => nil,
        )
        expect(etcd).to receive(:get).with('/kontena/test/test1').and_call_original

        expect{ TestEtcd.get('test1') }.to raise_error(TestEtcd::Invalid)
      end

      it 'raises Invalid if the etcd node is not JSON', :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1' => 'asdf',
        )
        expect(etcd).to receive(:get).with('/kontena/test/test1').and_call_original

        expect{ TestEtcd.get('test1') }.to raise_error(TestEtcd::Invalid, /Invalid JSON value: \d+: unexpected token at 'asdf/)
      end

    end

    describe '#create' do
      it 'returns new object stored to etcd', :etcd => true do
        expect(etcd).to receive(:set).with('/kontena/test/test1', '{"field":"value"}', prevExist: false).and_call_original

        subject = TestEtcd.create('test1', field: "value")

        expect(subject).to eq TestEtcd.new('test1', field: "value")
        expect(subject.etcd_index).to be > etcd_server.start_index

        expect(etcd_server.logs).to eq [
          [:create, '/kontena/test/test1'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/',
          '/kontena/test/',
          '/kontena/test/test1',
        ])
        expect(etcd_server.nodes).to eq(
          '/kontena/test/test1' => {'field' => "value"}
        )
        expect(etcd_server).to be_modified
      end

      it 'raises conflict if object exists in etcd', :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1' => { 'field' => "value 1" }
        )

        expect(etcd).to receive(:set).with('/kontena/test/test1', '{"field":"value 2"}', prevExist: false).and_call_original

        expect{TestEtcd.create('test1', field: "value 2")}.to raise_error(TestEtcd::Conflict, /Create conflict with \/kontena\/test\/test1@/)

        expect(etcd_server).to_not be_modified
      end
    end

    describe '#create_or_get' do
      it 'returns new object stored to etcd', :etcd => true do
        expect(etcd).to receive(:set).with('/kontena/test/test1', '{"field":"value"}', prevExist: false).and_call_original

        expect(TestEtcd.create_or_get('test1', field: "value")).to eq TestEtcd.new('test1', field: "value")

        expect(etcd_server.logs).to eq [
          [:create, '/kontena/test/test1'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/',
          '/kontena/test/',
          '/kontena/test/test1',
        ])
        expect(etcd_server.nodes).to eq(
          '/kontena/test/test1' => {'field' => "value"}
        )
        expect(etcd_server).to be_modified
      end

      it 'returns existing object loaded from etcd', :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1' => { 'field' => "value 1" }
        )

        expect(etcd).to receive(:set).with('/kontena/test/test1', '{"field":"value 2"}', prevExist: false).and_call_original
        expect(etcd).to receive(:get).with('/kontena/test/test1').and_call_original

        expect(TestEtcd.create_or_get('test1', field: "value 2")).to eq TestEtcd.new('test1', field: "value 1")

        expect(etcd_server).to_not be_modified
      end

      it 'raises conflict if the world is a scary place', :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1' => { 'field' => "value 1" }
        )

        # this is a create vs delete race
        expect(etcd).to receive(:set).with('/kontena/test/test1', '{"field":"value"}', prevExist: false).and_call_original
        expect(etcd).to receive(:get).with('/kontena/test/test1').and_raise(Kontena::Etcd::Error::KeyNotFound.new(index: 1, reason: '/kontena/test/test1', message: "Key not found" ))

        expect{TestEtcd.create_or_get('test1', field: "value")}.to raise_error(TestEtcd::Conflict, /Create-and-Delete conflict with \/kontena\/test\/test1@\d+: Key not found/)

        expect(etcd_server).to_not be_modified
      end
    end

    it 'lists from etcd', :etcd => true do
      etcd_server.load!(
        '/kontena/test/test1' => { 'field' => "value 1" },
        '/kontena/test/test2' => { 'field' => "value 2" },
      )

      expect(etcd).to receive(:get).with('/kontena/test/').and_call_original

      subject = TestEtcd.list

      expect(subject.sort).to eq [
        TestEtcd.new('test1', field: "value 1"),
        TestEtcd.new('test2', field: "value 2"),
      ]
      subject.each do |item|
        expect(item.etcd_index).to be > 0
      end

      expect(etcd_server).to_not be_modified
    end

    it 'lists empty if directory is missing in etcd', :etcd => true do
      expect(etcd).to receive(:get).with('/kontena/test/').and_call_original

      expect(TestEtcd.list()).to eq []

      expect(etcd_server).to_not be_modified
    end

    it 'lists empty if directory is empty in etcd', :etcd => true do
      etcd_server.load!(
        '/kontena/test/test1' => { 'field' => "value 1" },
      )
      etcd.delete('/kontena/test/test1')

      expect(etcd).to receive(:get).with('/kontena/test/').and_call_original

      expect(TestEtcd.list()).to be_empty
    end

    describe '#each' do
      it "Lists an empty directory from etcd", :etcd => true do
        etcd_server.load!(
          '/kontena/test/' => nil,
        )

        expect{|block| TestEtcd.each(&block)}.to_not yield_control
      end

      it "Lists one node from etcd", :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1' => { 'field' => "value 1" },
        )

        expect{|block| TestEtcd.each(&block)}.to yield_with_args(TestEtcd.new('test1', field: "value 1"))
      end

      it "Lists two nodes from etcd", :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1' => { 'field' => "value 1" },
          '/kontena/test/test2' => { 'field' => "value 2" },

        )

        expect{|block| TestEtcd.each(&block)}.to yield_successive_args(
          TestEtcd.new('test1', field: "value 1"),
          TestEtcd.new('test2', field: "value 2"),
        )
      end
    end

    describe '#delete' do
      it 'deletes instance from etcd', :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1' => { 'field' => "value 1" },
          '/kontena/test/test2' => { 'field' => "value 2" },
        )

        expect(etcd).to receive(:delete).with('/kontena/test/test1').and_call_original

        subject = TestEtcd.new('test1')
        subject.delete!

        expect(subject.etcd_index).to be > etcd_server.start_index

        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/test/test1'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/',
          '/kontena/test/',
          '/kontena/test/test2',
        ])
        expect(etcd_server.nodes).to eq(
          '/kontena/test/test2' => {'field' => "value 2"},
        )
        expect(etcd_server).to be_modified
      end

      it 'deletes everything from etcd recursively', :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1' => { 'field' => "value 1" },
          '/kontena/test/test2' => { 'field' => "value 2" },
        )

        expect(etcd).to receive(:delete).with('/kontena/test/', recursive: true).and_call_original

        TestEtcd.delete()

        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/test/'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/',
        ])
        expect(etcd_server).to be_modified
      end

      it 'deletes instance from etcd', :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1' => { 'field' => "value 1" },
          '/kontena/test/test2' => { 'field' => "value 2" },
        )

        expect(etcd).to receive(:delete).with('/kontena/test/test1', recursive: false).and_call_original

        TestEtcd.delete('test1')

        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/test/test1'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/',
          '/kontena/test/',
          '/kontena/test/test2',
        ])
        expect(etcd_server.nodes).to eq(
          '/kontena/test/test2' => {'field' => "value 2"},
        )
        expect(etcd_server).to be_modified
      end

      it 'raises for a non-existant directory', :etcd => true do
        expect(etcd).to receive(:delete).with('/kontena/test/', recursive: true).and_call_original

        expect{TestEtcd.delete()}.to raise_error(TestEtcd::NotFound)
      end

      it 'raises for a non-existant node', :etcd => true do
        etcd_server.load!(
          '/kontena/test/test2' => { 'field' => "value 2" },
        )

        expect(etcd).to receive(:delete).with('/kontena/test/test1', recursive: false).and_call_original

        expect{TestEtcd.delete('test1')}.to raise_error(TestEtcd::NotFound, /Removing non-existant node \/kontena\/test\/test1@/)
      end
    end

    describe '#rmdir' do
      it 'deletes an empty directory from etcd', :etcd => true do
        etcd_server.load!(
          '/kontena/test/' => nil,
        )

        expect(etcd).to receive(:delete).with('/kontena/test/', dir: true).and_call_original

        TestEtcd.rmdir()

        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/test/'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/',
        ])
        expect(etcd_server).to be_modified
      end

      it 'does not delete a non-empty directory from etcd', :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1' => { 'field' => "value 1" },
        )

        expect(etcd).to receive(:delete).with('/kontena/test/', dir: true).and_call_original

        expect{TestEtcd.rmdir()}.to raise_error(TestEtcd::Conflict, /Removing non-empty directory \/kontena\/test@/)

        expect(etcd_server).to_not be_modified
      end

      it 'raises for a non-existant directory', :etcd => true do
        expect(etcd).to receive(:delete).with('/kontena/test/', dir: true).and_call_original

        expect{TestEtcd.rmdir()}.to raise_error(TestEtcd::NotFound, /Removing non-existant directory \/kontena/) # XXX: suffix varies for FakeServers
      end
    end

    describe '#watch' do
      it "recursively walks the prefix from etcd", :etcd => true do
        etcd_server.load!(
          '/kontena/test/test1' => { 'field' => "value 1" },
          '/kontena/test/test2' => { 'field' => "value 2" },
        )

        step = 0

        TestEtcd.watch do |collection|
          case step += 1
          when 1
            expect(collection.map{|object| object.etcd_key}).to contain_exactly('/kontena/test/test1', '/kontena/test/test2')

            etcd.delete '/kontena/test/test2'

          when 2
            expect(collection.map{|object| object.etcd_key}).to contain_exactly('/kontena/test/test1')

            break
          end
        end
      end
    end
  end

  context 'for a complex model' do
    class TestEtcdChild
      include Kontena::JSON::Model
      include Kontena::Etcd::Model

      etcd_path '/kontena/test/:parent/children/:name'
      json_attr :field, type: String
    end

    it 'renders the path for the class' do
      expect(TestEtcdChild.etcd_schema.to_s).to eq '/kontena/test/:parent/children/:name'
    end

    it 'renders the path prefix for the class' do
      expect(TestEtcdChild.etcd_schema.prefix()).to eq '/kontena/test/'
      expect(TestEtcdChild.etcd_schema.prefix('parent1')).to eq '/kontena/test/parent1/children/'
    end

    it 'renders to path for the object' do
      expect(TestEtcdChild.new('parent1', 'child1').etcd_key).to eq '/kontena/test/parent1/children/child1'
    end

    describe '#mkdir' do
      it 'creates parent directory in etcd', :etcd => true do
        expect(etcd).to receive(:set).with('/kontena/test/', dir: true, prevExist: false).and_call_original

        TestEtcdChild.mkdir()

        expect(etcd_server.logs).to eq [
          [:create, '/kontena/test/'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/',
          '/kontena/test/',
        ])
        expect(etcd_server).to be_modified
      end

      it 'creates child directory in etcd', :etcd => true do
        expect(etcd).to receive(:set).with('/kontena/test/parent/children/', dir: true, prevExist: false).and_call_original

        TestEtcdChild.mkdir('parent')

        expect(etcd_server.logs).to eq [
          [:create, '/kontena/test/parent/children/'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/',
          '/kontena/test/',
          '/kontena/test/parent/',
          '/kontena/test/parent/children/',
        ])
        expect(etcd_server).to be_modified
      end

      it 'fails if given a full key' do
        expect{TestEtcdChild.mkdir('parent', 'child')}.to raise_error(ArgumentError)
      end
    end

    context 'with etcd having nodes' do
      before do
        etcd_server.load!(
          '/kontena/test/test1/children/childA' => { 'field' => "value 1A" },
          '/kontena/test/test1/children/childB' => { 'field' => "value 1B" },
          '/kontena/test/test2/children/childA' => { 'field' => "value 2A" },
          '/kontena/test/test2/children/childB' => { 'field' => "value 2B" },
        )
      end

      it 'lists recursively from etcd', :etcd => true do
        expect(TestEtcdChild.list().sort).to eq [
          TestEtcdChild.new('test1', 'childA', field: "value 1A"),
          TestEtcdChild.new('test1', 'childB', field: "value 1B"),
          TestEtcdChild.new('test2', 'childA', field: "value 2A"),
          TestEtcdChild.new('test2', 'childB', field: "value 2B"),
        ]

        expect(etcd_server).to_not be_modified
      end

      it 'lists etcd', :etcd => true do
        expect(TestEtcdChild.list('test1').sort).to eq [
          TestEtcdChild.new('test1', 'childA', field: "value 1A"),
          TestEtcdChild.new('test1', 'childB', field: "value 1B"),
        ]

        expect(etcd_server).to_not be_modified
      end

      it 'deletes instance from etcd', :etcd => true do
        expect(etcd).to receive(:delete).with('/kontena/test/test1/children/childA').and_call_original

        TestEtcdChild.new('test1', 'childA').delete!

        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/test/test1/children/childA'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/',
          '/kontena/test/',
          '/kontena/test/test1/',
          '/kontena/test/test1/children/',
          '/kontena/test/test1/children/childB',
          '/kontena/test/test2/',
          '/kontena/test/test2/children/',
          '/kontena/test/test2/children/childA',
          '/kontena/test/test2/children/childB',
        ])
        expect(etcd_server).to be_modified
      end

      it 'deletes one set of instances', :etcd => true do
        expect(etcd).to receive(:delete).with('/kontena/test/test1/children/', recursive: true).and_call_original

        TestEtcdChild.delete('test1')

        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/test/test1/children/'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/',
          '/kontena/test/',
          '/kontena/test/test1/',
          '/kontena/test/test2/',
          '/kontena/test/test2/children/',
          '/kontena/test/test2/children/childA',
          '/kontena/test/test2/children/childB',
        ])
        expect(etcd_server).to be_modified
      end

      it 'deletes everything from etcd recursively', :etcd => true do
        expect(etcd).to receive(:delete).with('/kontena/test/', recursive: true).and_call_original

        TestEtcdChild.delete()

        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/test/'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/',
        ])
        expect(etcd_server).to be_modified
      end
    end

    it 'fails if trying to delete with an invalid value' do
      expect{TestEtcdChild.delete(nil)}.to raise_error ArgumentError
      expect{TestEtcdChild.delete("")}.to raise_error ArgumentError
    end
  end

  context "For a model missing an etcd schema" do
    let :model do
      Class.new do
        include Kontena::JSON::Model
        include Kontena::Etcd::Model
      end
    end

    it "Raises an error on #initialize" do
      expect{model.new}.to raise_error(RuntimeError, /Missing etcd_path for/)
    end

    it "Raises an error on #get" do
      expect{model.get('test')}.to raise_error(RuntimeError, /Missing etcd_path for/)
    end
  end
end
