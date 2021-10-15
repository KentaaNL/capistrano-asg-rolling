# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::AMI do
  subject(:ami) { described_class.new('ami-12345', instance) }

  let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345', '192.168.1.88', '54.194.252.215', nil, nil) }

  describe '.create' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=CreateImage/).to_return(body: File.read('spec/support/stubs/CreateImage.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeImages/).to_return(body: File.read('spec/support/stubs/DescribeImages.xml'))
    end

    it 'calls the API with the given instance' do
      described_class.create(instance: instance, name: 'Test AMI')
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=CreateImage&InstanceId=i-12345&Name=Test%20AMI/).once
    end

    it 'calls the API to create tags' do
      described_class.create(instance: instance, name: 'Test AMI', tags: { 'Name' => 'Test tag' })
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=CreateImage&InstanceId=i-12345&Name=Test%20AMI&TagSpecification.1.ResourceType=image&TagSpecification.1.Tag.1.Key=Name&TagSpecification.1.Tag.1.Value=Test%20tag/).once
    end

    it 'returns an AMI object with the image ID' do
      ami = described_class.create(instance: instance, name: 'Test AMI')
      expect(ami.id).to eq('ami-1234567890EXAMPLE')
    end
  end

  describe '#exists?' do
    context 'when AMI exists' do
      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=DescribeImages/).to_return(body: File.read('spec/support/stubs/DescribeImages.xml'))
      end

      it 'returns true' do
        expect(ami.exists?).to be true
      end
    end

    context 'when AMI does not exist' do
      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=DescribeImages/).to_return(body: File.read('spec/support/stubs/DescribeImages.NotFound.xml'))
      end

      it 'returns false' do
        expect(ami.exists?).to be false
      end
    end
  end

  describe '#delete' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DeregisterImage/).to_return(body: File.read('spec/support/stubs/DeregisterImage.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeImages/).to_return(body: File.read('spec/support/stubs/DescribeImages.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DeleteSnapshot/).to_return(body: File.read('spec/support/stubs/DeleteSnapshot.xml'))
    end

    it 'calls the API to deregister the image' do
      ami.delete
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=DeregisterImage&ImageId=ami-12345/).once
    end

    it 'calls the API to delete the snapshots' do
      ami.delete
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=DeleteSnapshot&SnapshotId=snap-1234567890abcdef0/).once
    end
  end

  describe '#snapshots' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeImages/).to_return(body: File.read('spec/support/stubs/DescribeImages.xml'))
    end

    it 'calls the API to retrieve the snapshots' do
      ami.snapshots
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=DescribeImages&ImageId.1=ami-12345/).once
    end

    it 'returns an Array with Snapshot objects' do
      snapshots = ami.snapshots
      expect(snapshots).not_to be_empty
      expect(snapshots.first).to be_a(Capistrano::ASG::Rolling::Snapshot)
    end

    it 'sets the ID on Snapshot' do
      snapshot = ami.snapshots.first
      expect(snapshot.id).to eq('snap-1234567890abcdef0')
    end
  end
end
