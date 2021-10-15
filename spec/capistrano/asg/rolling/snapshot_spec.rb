# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::Snapshot do
  subject(:snapshot) { described_class.new('snap-1234567890abcdef0') }

  describe '#delete' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DeleteSnapshot/).to_return(body: File.read('spec/support/stubs/DeleteSnapshot.xml'))
    end

    it 'calls the API to delete the snapshot' do
      snapshot.delete
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=DeleteSnapshot&SnapshotId=snap-1234567890abcdef0/).once
    end
  end
end
