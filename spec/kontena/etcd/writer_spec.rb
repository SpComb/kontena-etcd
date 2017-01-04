describe Kontena::Etcd::Writer do
  context "without TTLs", :etcd => true do
    subject { described_class.new() }

    describe '#refresh' do
      it "raises ArgumentError" do
        expect{subject.refresh}.to raise_error(ArgumentError)
      end
    end

  end

  context "for an empty etcd", :etcd => true do
    subject { described_class.new(ttl: 30) }

    describe '#update' do
      it "writes out a node" do
        subject.update(
          '/kontena/test1' => { 'test' => 1 }.to_json,
        )

        expect(etcd_server.logs).to eq [
          [:set, '/kontena/test1'],
        ]
        expect(etcd_server.nodes).to eq(
          '/kontena/test1' => { 'test' => 1 },
        )
      end
    end

    describe '#refresh' do
      it "does nothing" do
        subject.refresh

        expect(etcd_server).to_not be_modified
      end
    end
  end

  context "for etcd with one node set", :etcd => true do
    subject { described_class.new(ttl: 30) }

    before do
      subject.update(
        '/kontena/test1' => { 'test' => 1 }.to_json,
      )
    end

    describe '#update' do
      it "keeps an existing node" do |ex|
        subject.update(
          '/kontena/test1' => { 'test' => 1 }.to_json,
        )

        expect(etcd_server.logs).to eq [
          [:set, '/kontena/test1'],
        ]
        expect(etcd_server.nodes).to eq(
          '/kontena/test1' => { 'test' => 1 },
        )
      end

      it "updates a node" do |ex|
        subject.update(
          '/kontena/test1' => { 'test' => 2 }.to_json,
        )

        expect(etcd_server.logs).to eq [
          [:set, '/kontena/test1'],
          [:set, '/kontena/test1'],
        ]
        expect(etcd_server.nodes).to eq(
          '/kontena/test1' => { 'test' => 2 },
        )
      end

      it "deletes a node" do |ex|
        subject.update({})

        expect(etcd_server.logs).to eq [
          [:set, '/kontena/test1'],
          [:compareAndDelete, '/kontena/test1'],
        ]
        expect(etcd_server.nodes).to eq({})
      end

      it "replaces a node" do |ex|
        subject.update(
          '/kontena/test2' => { 'test' => 2 }.to_json,
        )

        expect(etcd_server.logs).to eq [
          [:set, '/kontena/test1'],
          [:set, '/kontena/test2'],
          [:compareAndDelete, '/kontena/test1'],
        ]
        expect(etcd_server.nodes).to eq(
          '/kontena/test2' => { 'test' => 2 },
        )
      end
    end

    describe '#refresh' do
      it "updates the node" do
        subject.refresh

        expect(etcd_server.logs).to eq [
          [:set, '/kontena/test1'],
        ]
        expect(etcd_server.nodes).to eq(
          '/kontena/test1' => { 'test' => 1 },
        )
      end

      it "raises if the node has expired", :fake_etcd => true do
        etcd_server.tick! 30.0

        expect{subject.refresh}.to raise_error(Kontena::Etcd::Error::KeyNotFound)

        expect(etcd_server.logs).to eq [
          [:set, '/kontena/test1'],
          [:expire, '/kontena/test1'],
        ]
        expect(etcd_server.nodes).to eq({})
      end

      it "raises if the node has been modified", :fake_etcd => true do
        etcd.set '/kontena/test1', 'lollerskates'

        expect{subject.refresh}.to raise_error(Kontena::Etcd::Error::TestFailed)
      end
    end

    describe '#clear' do
      it "removes the nodes" do
        subject.clear

        expect(etcd_server.logs).to eq [
          [:set, '/kontena/test1'],
          [:compareAndDelete, '/kontena/test1'],
        ]
        expect(etcd_server.nodes).to eq({})
      end
    end

    describe '#remove' do
      it "removes an updated node" do
        subject.update(
          '/kontena/test1' => { 'test' => 1 }.to_json,
        )

        subject.clear

        expect(etcd_server.logs).to eq [
          [:set, '/kontena/test1'],
          [:compareAndDelete, '/kontena/test1'],
        ]
        expect(etcd_server.nodes).to eq({})
      end

      it "removes a refreshed node" do
        subject.update(
          '/kontena/test1' => { 'test' => 1 }.to_json,
        )

        subject.refresh
        subject.clear

        expect(etcd_server.logs).to eq [
          [:set, '/kontena/test1'],
          [:compareAndDelete, '/kontena/test1'],
        ]
        expect(etcd_server.nodes).to eq({})
      end

      it "does not remove a modified node" do
        subject.update(
          '/kontena/test1' => { 'test' => 1 }.to_json,
        )

        etcd.set('/kontena/test1', { 'test' => 2}.to_json)

        subject.clear

        expect(etcd_server.logs).to eq [
          [:set, '/kontena/test1'],
          [:set, '/kontena/test1'],
        ]
        expect(etcd_server.nodes).to eq(
          '/kontena/test1' => { 'test' => 2 },
        )
      end
    end
  end
end
