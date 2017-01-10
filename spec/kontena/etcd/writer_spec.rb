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
        expect(subject.shared? '/kontena/test1').to be_nil
      end

      it "overrides a conflicting node" do
        etcd_server.load!({
          '/kontena/test1' => { 'test' => 0 },
        }, ttl: 30)

        subject.update(
          '/kontena/test1' => { 'test' => 1 }.to_json,
        )
        expect(subject.shared? '/kontena/test1').to be_nil

        expect(etcd_server.nodes).to eq(
          '/kontena/test1' => { 'test' => 1 },
        )
      end

      it "detects a shared node" do
        etcd_server.load!({
          '/kontena/test1' => { 'test' => 1 },
        }, ttl: 30)

        subject.update(
          '/kontena/test1' => { 'test' => 1 }.to_json,
        )
        expect(subject.shared? '/kontena/test1').to_not be_nil

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
        # external write conflict
        etcd.set '/kontena/test1', 'lollerskates'

        expect{subject.refresh}.to raise_error(Kontena::Etcd::Error::TestFailed)
      end

      it "marks the node as shared", :fake_etcd => true do
        # external refresh
        etcd.refresh '/kontena/test1', 30

        expect{subject.refresh}.to_not raise_error

        expect(subject.shared? '/kontena/test1').to_not be_nil
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

  context "for a shared node in etcd", :etcd => true do
    subject { described_class.new(ttl: 30) }

    before do
      subject.update(
        '/kontena/test1' => { 'test' => 1 }.to_json,
      )

      # external refresh
      etcd.refresh '/kontena/test1', 30

      expect{subject.refresh}.to_not raise_error

      expect(subject.shared? '/kontena/test1').to_not be_nil
    end

    it "does not remove the shared node" do
      subject.clear

      expect(etcd_server.nodes).to eq(
        '/kontena/test1' => { 'test' => 1 },
      )
    end

    it "keeps it marked as shared if concurrently refreshed", :fake_etcd => true do
      # tick a bit, but not enough to expire the old shared value
      etcd_server.tick! 20
      subject.refresh
      expect(subject.shared? '/kontena/test1').to_not be_nil

      # external refresh
      etcd.refresh '/kontena/test1', 30

      # tick a bit more, enough to expire the old shared value
      etcd_server.tick! 20
      subject.refresh
      expect(subject.shared? '/kontena/test1').to_not be_nil
    end

    it "un-marks it as shared if it would have expired", :fake_etcd => true do
      # tick a bit, but not enough to expire the old shared value
      etcd_server.tick! 20
      subject.refresh
      expect(subject.shared? '/kontena/test1').to_not be_nil

      # tick a bit more, enough to expire the old shared value
      etcd_server.tick! 20
      subject.refresh
      expect(subject.shared? '/kontena/test1').to be_nil
    end
  end
end
