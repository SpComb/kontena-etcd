require 'kontena/json'

require 'ipaddr'

describe Kontena::JSON::Model do
  # TODO: use anonymous class
  class TestJSON
    include Kontena::JSON::Model

    json_attr :str, omitnil: true
    json_attr :int, name: 'number', omitnil: true
    json_attr :bool, default: false, readonly: true
    json_attr :ipaddr, type: IPAddr
  end

  it 'initializes default attributes' do
    subject = TestJSON.new()

    expect(subject.str).to be_nil
    expect(subject.int).to be_nil
    expect(subject.bool).to be false
    expect(subject.ipaddr).to be_nil
  end

  it 'initializes json attributes' do
    subject = TestJSON.new(str: "string", int: 2, bool: true, ipaddr: IPAddr.new("127.0.0.1"))

    expect(subject.str).to eq "string"
    expect(subject.int).to eq 2
    expect(subject.bool).to eq true
    expect(subject.ipaddr).to eq IPAddr.new("127.0.0.1")
  end

  it 'makes attributes readonly' do
    subject = TestJSON.new(str: "string", int: 2, bool: true, ipaddr: IPAddr.new("127.0.0.1"))

    expect{subject.str = "string 2"}.to_not raise_error
    expect{subject.bool = false}.to raise_error(NoMethodError)
  end

  it 'compares equal' do
    expect(TestJSON.new()).to eq TestJSON.new()
    expect(TestJSON.new(str: "string")).to eq TestJSON.new(str: "string")
    expect(TestJSON.new(str: "string", int: 5)).to eq TestJSON.new(str: "string", int: 5)
    expect(TestJSON.new(str: "string", ipaddr: IPAddr.new("127.0.0.1"))).to eq TestJSON.new(str: "string", ipaddr: IPAddr.new("127.0.0.1"))
  end

  it 'compares unequal' do
    expect(TestJSON.new(str: "string")).to_not eq TestJSON.new()
    expect(TestJSON.new(str: "string")).to_not eq TestJSON.new(str: "different")
    expect(TestJSON.new(str: "string")).to_not eq TestJSON.new(int: 5)
    expect(TestJSON.new(str: "test", ipaddr: IPAddr.new("127.0.0.1"))).to_not eq TestJSON.new(str: "test", ipaddr: IPAddr.new("127.0.0.2"))
  end

  it 'encodes to json with default values' do
    expect(JSON.parse(TestJSON.new().to_json)).to eq({'bool' => false, 'ipaddr' => nil})
  end

  it 'encodes to json with simple value' do
    expect(JSON.parse(TestJSON.new(str: "test").to_json)).to eq({'str' => "test", 'bool' => false, 'ipaddr' => nil})
  end

  it 'encodes to json with name' do
    expect(JSON.parse(TestJSON.new(int: 5).to_json)).to eq({'number' => 5, 'bool' => false, 'ipaddr' => nil})
  end

  it 'encodes to json with overriden default value' do
    expect(JSON.parse(TestJSON.new(str: "test", int: 5, bool: true).to_json)).to eq({'str' => "test", 'number' => 5, 'bool' => true, 'ipaddr' => nil})
  end

  it 'encodes to json with type value #to_json' do
   expect(JSON.parse(TestJSON.new(ipaddr: IPAddr.new("127.0.0.1")).to_json)).to eq({'bool' => false, 'ipaddr' => "127.0.0.1"})
 end

  it 'decodes from json with default values' do
    expect(TestJSON.from_json('{}')).to eq TestJSON.new()
  end

  it 'decodes from json' do
    expect(TestJSON.from_json('{"str": "test"}')).to eq TestJSON.new(str: "test")
    expect(TestJSON.from_json('{"bool": true}')).to eq TestJSON.new(bool: true)
    expect(TestJSON.from_json('{"bool": false}')).to eq TestJSON.new()
  end

  it 'decodes from json with name' do
    expect(TestJSON.from_json('{"number": 5}')).to eq TestJSON.new(int: 5)
  end

  it 'decodes with type' do
    expect(TestJSON.from_json('{"ipaddr": "127.0.0.1"}')).to eq TestJSON.new(ipaddr: IPAddr.new("127.0.0.1"))
    expect(TestJSON.from_json('{"ipaddr": "127.0.0.1/8"}')).to eq TestJSON.new(ipaddr: IPAddr.new("127.0.0.1/8"))
    expect(TestJSON.from_json('{"ipaddr": "127.0.0.1/32"}').ipaddr.to_s).to eq "127.0.0.1"

  end

  it 'ignores unknown attributes' do
    expect(TestJSON.from_json('{"foo": "bar"}')).to eq TestJSON.new()
    expect(TestJSON.from_json('{"str": "test", "foo": "bar"}')).to eq TestJSON.new(str: "test")
  end

  context "for an empty model" do
    class TestJSONEmpty
      include Kontena::JSON::Model
    end

    it 'initializes no attributes' do
      subject = TestJSONEmpty.new()
    end

    it 'compares equal' do
      expect(TestJSONEmpty.new()).to eq TestJSONEmpty.new()
    end

    it 'encodes to json' do
      expect(TestJSONEmpty.new().to_json).to eq('{}')
    end

    it 'decodes from json' do
      expect(TestJSONEmpty.from_json('{}')).to eq TestJSONEmpty.new()
    end
  end

  context "for a nested model" do
    let :child_model do
      Class.new do
        include Kontena::JSON::Model

        json_attr :field
      end
    end

    let :parent_model do
      cm = child_model

      Class.new do
        include Kontena::JSON::Model

        json_attr :child, model: cm
      end
    end

    it "Decodes from JSON" do
      expect(parent_model.json_attrs[:child].model).to be child_model

      subject = parent_model.from_json('{"child": {"field": "value"}}')

      expect(subject).to be_a parent_model
      expect(subject.child).to be_a child_model
      expect(subject.child.field).to eq "value"
    end

    it "Encodes to JSON" do
      subject = parent_model.new(child: child_model.new(field: "value"))

      expect(subject.to_json).to eq '{"child":{"field":"value"}}'
    end
  end

  context "for an array model" do
    let :child_model do
      Class.new do
        include Kontena::JSON::Model

        json_attr :field
      end
    end

    let :array_model do
      cm = child_model

      Class.new do
        include Kontena::JSON::Model

        json_attr :children, array_model: cm
      end
    end

    it "Decodes from JSON" do
      subject = array_model.from_json('{"children": [{"field": "value"}]}')

      expect(subject).to be_a array_model
      expect(subject.children.first).to be_a child_model
      expect(subject.children.first.field).to eq "value"
    end

    it "Encodes to JSON" do
      subject = array_model.new(children: [child_model.new(field: "value")])

      expect(subject.to_json).to eq '{"children":[{"field":"value"}]}'
    end
  end

  context "for a recursive model" do
    let :model do
      Class.new do |cls|
        include Kontena::JSON::Model

        json_attr :parent, model: cls
      end
    end

    it "load raises a nested error" do
      expect{model.from_json('{"parent": {"parent": "asdf"}}')}.to raise_error(NoMethodError, /Loading #<Class:0x\w+>@parent: Loading #<Class:0x\w+>@parent: Loading #<Class:0x\w+>@parent: undefined method `fetch' for "asdf":String/)
    end
  end

  context "for an inherited model" do
    let :parent_model do
      Class.new do
        include Kontena::JSON::Model

        json_attr :parent
      end
    end

    let :child_model do
      Class.new(parent_model) do
        include Kontena::JSON::Model

        json_attr :child
      end
    end

    it "Decodes child model from JSON" do
      expect(child_model.json_attrs[:child]).to be_a Kontena::JSON::Attribute

      subject = child_model.from_json('{"child": "value1", "parent": "value2"}')

      expect(subject).to be_a child_model
      expect(subject.parent).to eq "value2"
      expect(subject.child).to eq "value1"
    end

    it "Encodes child model to JSON" do
      subject = child_model.new(child: "value1", parent: "value2")

      expect(JSON.load(subject.to_json)).to eq({"child" => "value1", "parent" => "value2"})
    end

    it "Decodes parent model from JSON" do
      expect(parent_model.json_attrs[:child]).to be_nil

      subject = parent_model.from_json('{"parent": "value2"}')

      expect(subject).to be_a parent_model
      expect(subject.parent).to eq "value2"
      expect{subject.child}.to raise_error(NoMethodError)
    end

    it "Encodes child model to JSON" do
      subject = parent_model.new(parent: "value2")

      expect(subject.to_json).to eq '{"parent":"value2"}'
    end

    it "Rejects child model attributes" do
      expect{parent_model.new(child: "value1", parent: "value2")}.to raise_error(ArgumentError)
    end
  end
end
