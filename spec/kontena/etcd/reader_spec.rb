describe Kontena::Etcd::Reader do
  context "For etcd with several test nodes" do
    subject do
      described_class.new('/kontena/test')
    end

    before do
      etcd_server.load!(
        '/kontena/test/test1' => { 'field' => "value 1" },
        '/kontena/test/test2' => { 'field' => "value 2" },
      )
    end

    it "recursively loads the prefixed nodes from etcd", :etcd => true do
      subject.sync

      expect(subject.map{|node| node.key}).to contain_exactly('/kontena/test/test1', '/kontena/test/test2')
      expect(JSON.parse(subject['/kontena/test/test1'].value)).to eq 'field' => "value 1"
    end

    it "adds a new node", :etcd => true do
      subject.sync

      etcd.set '/kontena/test/test3', value: { 'field' => "value 3" }.to_json

      subject.watch

      expect(subject.map{|node| node.key}).to contain_exactly(
        '/kontena/test/test1',
        '/kontena/test/test2',
        '/kontena/test/test3',
      )
    end

    it "updates a node", :etcd => true do
      subject.sync

      etcd.set '/kontena/test/test1', value: { 'field' => "value 1-B" }.to_json

      subject.watch

      expect(subject.map{|node| node.key}).to contain_exactly(
        '/kontena/test/test1',
        '/kontena/test/test2',
      )
      expect(JSON.parse(subject['/kontena/test/test1'].value)).to eq 'field' => "value 1-B"
    end

    it "removes a node", :etcd => true do
      subject.sync

      etcd.delete '/kontena/test/test2'

      subject.watch

      expect(subject.map{|node| node.key}).to contain_exactly(
        '/kontena/test/test1',
      )
    end
  end
end
