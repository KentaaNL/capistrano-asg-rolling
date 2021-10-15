# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::Instances do
  subject(:instances) { described_class.new }

  let(:group) { Capistrano::ASG::Rolling::AutoscaleGroup.new('test-asg', user: 'deployer') }
  let(:instance1) { Capistrano::ASG::Rolling::Instance.new('i-12345', '192.168.1.88', '54.194.252.215', 'ami-12345', group) }
  let(:instance2) { Capistrano::ASG::Rolling::Instance.new('i-67890', '192.168.1.44', '54.194.252.205', 'ami-67890', group) }

  before do
    instances << instance1
    instances << instance2
  end

  describe '#each' do
    it 'returns an Enumerator' do
      expect(instances.each).to be_a(Enumerator)
    end
  end

  describe '#empty?' do
    context 'when collection is not empty' do
      it 'returns false' do
        expect(instances).not_to be_empty
      end
    end

    context 'when collection is empty' do
      it 'returns true' do
        empty_instances = described_class.new
        expect(empty_instances).to be_empty
      end
    end
  end

  describe '#auto_terminate' do
    it 'returns an Instances object' do
      expect(instances.auto_terminate).to be_a(described_class)
    end

    it 'returns an empty set when no instances marked to auto terminate' do
      instance1.auto_terminate = false
      instance2.auto_terminate = false
      expect(instances.auto_terminate.count).to eq(0)
    end

    it 'returns instances that are marked marked to auto terminate' do
      instance1.auto_terminate = false
      expect(instances.auto_terminate.count).to eq(1)
      expect(instances.auto_terminate).to include(instance2)
    end
  end

  describe '#with_image' do
    it 'returns an Instances object' do
      expect(instances.with_image('ami-12345')).to be_a(described_class)
    end

    it 'returns an empty set when AMI ID does not match' do
      expect(instances.with_image('ami-54321').count).to eq(0)
    end

    it 'returns instances with the matching AMI ID' do
      expect(instances.with_image('ami-12345').count).to eq(1)
      expect(instances.with_image('ami-12345')).to include(instance1)
      expect(instances.with_image('ami-67890').count).to eq(1)
      expect(instances.with_image('ami-67890')).to include(instance2)
    end
  end

  describe '#wait_for_ssh' do
    before do
      allow(Capistrano::ASG::Rolling::SSH).to receive(:test?).and_return(true)
    end

    it 'waits until SSH is available on all instances' do
      instances.wait_for_ssh
      expect(Capistrano::ASG::Rolling::SSH).to have_received(:test?).with('192.168.1.88', 'deployer', nil).once
      expect(Capistrano::ASG::Rolling::SSH).to have_received(:test?).with('192.168.1.44', 'deployer', nil).once
    end
  end

  describe '#stop' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=StopInstances/).to_return(body: File.read('spec/support/stubs/StopInstances.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeInstances/).to_return(body: File.read('spec/support/stubs/DescribeInstances.Stopped.xml'))
    end

    it 'stops all instances' do
      instances.stop
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=StopInstances&InstanceId.1=i-12345/).once
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=StopInstances&InstanceId.1=i-67890/).once
    end
  end

  describe '#terminate' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=TerminateInstances/).to_return(body: File.read('spec/support/stubs/TerminateInstances.xml'))
    end

    it 'terminates all instances' do
      instances.terminate
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=TerminateInstances&InstanceId.1=i-12345/).once
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=TerminateInstances&InstanceId.1=i-67890/).once
    end

    it 'excludes the terminated instances from the collection' do
      expect(instances).to include(instance1, instance2)
      instances.terminate
      expect(instances).not_to include(instance1, instance2)
    end
  end

  describe '#create_ami' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=CreateImage/).to_return(body: File.read('spec/support/stubs/CreateImage.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeImages/).to_return(body: File.read('spec/support/stubs/DescribeImages.xml'))
    end

    it 'creates an AMI for all instances' do
      instances.create_ami
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=CreateImage&InstanceId=i-12345/).once
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=CreateImage&InstanceId=i-67890/).once
    end

    it 'returns an array with the AMIs' do
      result = instances.create_ami
      expect(result.size).to eq(2)

      (0..1).each do |index|
        ami = result[index]
        expect(ami).to be_a(Capistrano::ASG::Rolling::AMI)
        expect(ami.id).to eq('ami-1234567890EXAMPLE')
      end
    end
  end
end
