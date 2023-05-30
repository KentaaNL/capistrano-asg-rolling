# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::AutoscaleGroup do
  subject(:group) { described_class.new('test-asg') }

  let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345678', '192.168.1.88', '54.194.252.215', nil, group) }

  before do
    stub_request(:post, /amazonaws.com/)
      .with(body: /Action=DescribeAutoScalingGroups/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingGroups.xml'))
  end

  describe '#exists?' do
    context 'when auto scale group exists' do
      it 'returns true' do
        expect(group.exists?).to be true
      end
    end

    context 'when auto scale group does not exist' do
      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=DescribeAutoScalingGroups/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingGroups.Empty.xml'))
      end

      it 'returns false' do
        expect(group.exists?).to be false
      end
    end
  end

  describe '#launch_template' do
    context 'when launch template is not present' do
      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=DescribeAutoScalingGroups/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingGroups.NoLaunchTemplate.xml'))
      end

      it 'raises a NoLaunchTemplate exception' do
        expect { group.launch_template }.to raise_error(Capistrano::ASG::Rolling::NoLaunchTemplate)
      end
    end

    it 'returns a LaunchTemplate object with ID and version' do
      launch_template = group.launch_template
      expect(launch_template).to be_a(Capistrano::ASG::Rolling::LaunchTemplate)
      expect(launch_template.id).to eq('lt-0a20c965061f64abc')
      expect(launch_template.version).to eq('1')
    end
  end

  describe '#subnet_ids' do
    it 'returns the subnet IDs as an Array' do
      expect(group.subnet_ids).to eq(%w[subnet-12345678 subnet-98765432])
    end
  end

  describe '#instance_warmup_time' do
    it 'returns the warmup time for instances, also known as health check grace period' do
      expect(group.instance_warmup_time).to eq(300)
    end
  end

  describe '#healthy_percentage' do
    context 'when no value is set' do
      it 'returns the default healthy percentage (100)' do
        expect(group.healthy_percentage).to eq(100)
      end
    end

    context 'when a value is set' do
      subject(:group) { described_class.new('test-asg', healthy_percentage: 50) }

      it 'returns the value set in the configuration (50)' do
        expect(group.healthy_percentage).to eq(50)
      end
    end
  end

  describe '#start_instance_refresh' do
    let(:template) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 1, 'MyLaunchTemplate') }

    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=StartInstanceRefresh&AutoScalingGroupName=test-asg/).to_return(body: File.read('spec/support/stubs/StartInstanceRefresh.xml'))
    end

    it 'calls the API to start instance refresh for the given auto scale group' do
      group.start_instance_refresh(template)
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=StartInstanceRefresh&AutoScalingGroupName=test-asg/).once
    end

    context 'when instance refresh is already in progress' do
      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=StartInstanceRefresh&AutoScalingGroupName=test-asg/).to_return(body: File.read('spec/support/stubs/StartInstanceRefresh.InProgress.xml'), status: 400)
      end

      it 'raises an InstanceRefreshFailed exception' do
        expect { group.start_instance_refresh(template) }.to raise_error(Capistrano::ASG::Rolling::InstanceRefreshFailed, 'An Instance Refresh is already in progress and blocks the execution of this Instance Refresh.')
      end
    end
  end

  describe '#instances' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeInstances/).to_return(body: File.read('spec/support/stubs/DescribeInstances.Running.xml'))
    end

    it 'returns an Array with Instance objects that are in service' do
      instances = group.instances
      expect(instances.count).to eq(1)
    end

    it 'sets the ID, IP address, image ID attributes on Instance' do
      instance = group.instances.first
      expect(instance.id).to eq('i-1234567890abcdef0')
      expect(instance.private_ip_address).to eq('192.168.1.88')
      expect(instance.image_id).to eq('ami-bff32ccc')
      expect(instance.autoscale_group).to eq(group)
    end
  end

  describe '#enter_standby' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=EnterStandby/).to_return(body: File.read('spec/support/stubs/EnterStandby.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeAutoScalingInstances/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingInstances.Standby.xml'))
    end

    it 'moves the instance into standby state' do
      group.enter_standby(instance)
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=EnterStandby&AutoScalingGroupName=test-asg&InstanceIds.member.1=i-12345678&ShouldDecrementDesiredCapacity=true/).once
    end
  end

  describe '#exit_standby' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=ExitStandby/).to_return(body: File.read('spec/support/stubs/ExitStandby.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeAutoScalingInstances/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingInstances.InService.xml'))
    end

    it 'moves the instance out of standby state' do
      group.exit_standby(instance)
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=ExitStandby&AutoScalingGroupName=test-asg&InstanceIds.member.1=i-12345678/).once
    end
  end

  describe '#rolling?' do
    it 'defaults to rolling deployment when option is absent' do
      expect(group.rolling?).to be true
    end

    context 'with rolling property set to true' do
      subject(:group) { described_class.new('test-asg', rolling: true) }

      it 'is a rolling deployment' do
        expect(group.rolling?).to be true
      end
    end

    context 'with rolling property set to false' do
      subject(:group) { described_class.new('test-asg', rolling: false) }

      it 'is not a rolling deployment' do
        expect(group.rolling?).to be false
      end
    end
  end
end
