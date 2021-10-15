# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::Instance do
  subject(:instance) { described_class.new('i-12345', '192.168.1.88', '54.194.252.215', 'ami-12345', group) }

  let(:group) { Capistrano::ASG::Rolling::AutoscaleGroup.new('test-asg', user: 'deployer') }

  before do
    stub_request(:post, /amazonaws.com/)
      .with(body: /Action=DescribeAutoScalingGroups/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingGroups.xml'))
    stub_request(:post, /amazonaws.com/)
      .with(body: /Action=DescribeLaunchTemplateVersions/).to_return(body: File.read('spec/support/stubs/DescribeLaunchTemplateVersions.xml'))
  end

  describe '.run' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=RunInstances/).to_return(body: File.read('spec/support/stubs/RunInstances.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeInstances/).to_return(body: File.read('spec/support/stubs/DescribeInstances.Running.xml'))
    end

    it 'calls the API to create a new Instance' do
      described_class.run(autoscaling_group: group)
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=RunInstances.*LaunchTemplate.LaunchTemplateId=lt-0a20c965061f64abc.*TagSpecification.1.ResourceType=instance&TagSpecification.1.Tag.1.Key=Name&TagSpecification.1.Tag.1.Value=Deployment%20for%20test-asg/).once
    end

    it 'returns an Instance object with all attributes set' do
      instance = described_class.run(autoscaling_group: group)
      expect(instance.id).to eq('i-1234567890abcdef0')
      expect(instance.private_ip_address).to eq('192.168.1.88')
      expect(instance.image_id).to eq('ami-bff32ccc')
      expect(instance.autoscale_group).to eq(group)
    end

    context 'with overrides' do
      it 'calls the API to create a new Instance with custom user data' do
        described_class.run(autoscaling_group: group, overrides: { user_data: Base64.encode64('#cloud-config') })
        expect(WebMock).to have_requested(:post, /amazonaws.com/)
          .with(body: /Action=RunInstances.*LaunchTemplate.LaunchTemplateId=lt-0a20c965061f64abc.*UserData=I2Nsb3VkLWNvbmZpZw%3D%3D%0/).once
      end

      it 'calls the API to create a new Instance with custom security group IDs' do
        described_class.run(autoscaling_group: group, overrides: { security_group_ids: ['sg-e4076980'] })
        expect(WebMock).to have_requested(:post, /amazonaws.com/)
          .with(body: /Action=RunInstances.*LaunchTemplate.LaunchTemplateId=lt-0a20c965061f64abc.*SecurityGroupId.1=sg-e4076980/).once
      end
    end
  end

  describe '#wait_for_ssh' do
    before do
      allow(Capistrano::ASG::Rolling::SSH).to receive(:test?).and_return(true)
    end

    it 'waits until SSH is available' do
      instance.wait_for_ssh
      expect(Capistrano::ASG::Rolling::SSH).to have_received(:test?).with('192.168.1.88', 'deployer', nil).once
    end
  end

  describe '#ip_address' do
    context 'with use_private_ip_address set to true' do
      before { Capistrano::ASG::Rolling::Configuration.set(:asg_rolling_use_private_ip_address, true) }

      it 'returns the private IP address' do
        expect(instance.ip_address).to eq('192.168.1.88')
      end
    end

    context 'with use_private_ip_address set to false' do
      before { Capistrano::ASG::Rolling::Configuration.set(:asg_rolling_use_private_ip_address, false) }

      it 'returns the public IP address' do
        expect(instance.ip_address).to eq('54.194.252.215')
      end
    end
  end

  describe '#stop' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=StopInstances/).to_return(body: File.read('spec/support/stubs/StopInstances.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeInstances/).to_return(body: File.read('spec/support/stubs/DescribeInstances.Stopped.xml'))
    end

    it 'calls the API to stop the instance' do
      instance.stop
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=StopInstances&InstanceId.1=i-12345/).once
    end
  end

  describe '#terminate' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=TerminateInstances/).to_return(body: File.read('spec/support/stubs/TerminateInstances.xml'))
    end

    it 'calls the API to terminate the instance' do
      instance.terminate
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=TerminateInstances&InstanceId.1=i-12345/).once
    end

    it 'sets terminated to true' do
      expect(instance.terminated?).to be false
      instance.terminate
      expect(instance.terminated?).to be true
    end
  end

  describe '#create_ami' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=CreateImage/).to_return(body: File.read('spec/support/stubs/CreateImage.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeImages/).to_return(body: File.read('spec/support/stubs/DescribeImages.xml'))
    end

    it 'calls the API to create an AMI for this instance' do
      instance.create_ami(name: 'Test AMI')
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=CreateImage&InstanceId=i-12345&Name=Test%20AMI/).once
    end

    it 'calls the API to create tags for the AMI' do
      instance.create_ami(name: 'Test AMI')
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=CreateImage&InstanceId=i-12345&Name=Test%20AMI&TagSpecification.1.ResourceType=image&TagSpecification.1.Tag.1.Key=Name&TagSpecification.1.Tag.1.Value=Deployment%20for%20test-asg/).once
    end

    it 'returns an AMI object with the image ID' do
      ami = instance.create_ami(name: 'Test AMI')
      expect(ami.id).to eq('ami-1234567890EXAMPLE')
    end
  end
end
