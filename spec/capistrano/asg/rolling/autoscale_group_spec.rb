# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::AutoscaleGroup do
  subject(:group) { described_class.new('test-asg') }

  let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345678', '192.168.1.88', '54.194.252.215', nil, group) }

  before do
    stub_request(:post, /amazonaws.com/)
      .with(body: /Action=DescribeAutoScalingGroups/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingGroups.xml'))
  end

  describe '#initialize' do
    it 'raises an ArgumentError when min healthy percentage > 100' do
      expect { described_class.new('test-asg', min_healthy_percentage: 101) }.to raise_error(ArgumentError, 'Property `min_healthy_percentage` must be between 0-100.')
    end

    it 'raises an ArgumentError when min healthy percentage is not present' do
      expect { described_class.new('test-asg', max_healthy_percentage: 100) }.to raise_error(ArgumentError, 'Property `min_healthy_percentage` must be specified when using `max_healthy_percentage`.')
    end

    it 'raises an ArgumentError when max healthy percentage < 100' do
      expect { described_class.new('test-asg', max_healthy_percentage: 99) }.to raise_error(ArgumentError, 'Property `max_healthy_percentage` must be between 100-200.')
    end

    it 'raises an ArgumentError when max healthy percentage > 200' do
      expect { described_class.new('test-asg', max_healthy_percentage: 201) }.to raise_error(ArgumentError, 'Property `max_healthy_percentage` must be between 100-200.')
    end

    it 'raises an ArgumentError when difference of min and max healthy percentage > 100' do
      expect { described_class.new('test-asg', min_healthy_percentage: 10, max_healthy_percentage: 111) }.to raise_error(ArgumentError, 'The difference between `min_healthy_percentage` and `max_healthy_percentage` must not be greater than 100.')
    end
  end

  it { expect(described_class::COMPLETED_REFRESH_STATUSES).to eq %w[Successful Failed Cancelled RollbackSuccessful RollbackFailed] }

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

  describe '#auto_rollback' do
    subject(:group) { described_class.new('test-asg', asg_instance_refresh_auto_rollback: false) }

    it 'returns the value set in the configuration' do
      expect(group.auto_rollback).to be false
    end

    context 'when no value is set' do
      subject(:group) { described_class.new('test-asg', {}) }

      it 'returns `nil`' do
        expect(group.auto_rollback).to be_nil
      end
    end
  end

  describe '#min_healthy_percentage' do
    context 'when no value is set' do
      it 'returns nil' do
        expect(group.min_healthy_percentage).to be_nil
      end
    end

    context 'when a value is set' do
      subject(:group) { described_class.new('test-asg', min_healthy_percentage: 50) }

      it 'returns the value set in the configuration (50)' do
        expect(group.min_healthy_percentage).to eq(50)
      end
    end
  end

  describe '#max_healthy_percentage' do
    context 'when no value is set' do
      it 'returns nil' do
        expect(group.max_healthy_percentage).to be_nil
      end
    end

    context 'when a value is set' do
      subject(:group) { described_class.new('test-asg', min_healthy_percentage: 90, max_healthy_percentage: 110) }

      it 'returns the value set in the configuration (110)' do
        expect(group.max_healthy_percentage).to eq(110)
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

    it 'sets instance refresh details on the group' do
      group.start_instance_refresh(template)
      expect(group.refresh_id).to eq 'ccfd3c2f-edb3-470d-af32-52cc57d201ca'
    end

    context 'when instance refresh is already in progress' do
      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=StartInstanceRefresh&AutoScalingGroupName=test-asg/).to_return(body: File.read('spec/support/stubs/StartInstanceRefresh.InProgress.xml'), status: 400)
      end

      it 'raises an StartInstanceRefreshError exception' do
        expect { group.start_instance_refresh(template) }.to raise_error(Capistrano::ASG::Rolling::StartInstanceRefreshError, 'An Instance Refresh is already in progress and blocks the execution of this Instance Refresh.')
      end
    end

    context 'when min and max healthy percentage is set' do
      subject(:group) { described_class.new('test-asg', min_healthy_percentage: 50, max_healthy_percentage: 110) }

      it 'calls the API to start instance refresh with the given healthy percentages' do
        group.start_instance_refresh(template)
        expect(WebMock).to have_requested(:post, /amazonaws.com/)
          .with(body: /Action=StartInstanceRefresh&AutoScalingGroupName=test-asg&DesiredConfiguration.LaunchTemplate.LaunchTemplateId=lt-1234567890&DesiredConfiguration.LaunchTemplate.Version=1&Preferences.InstanceWarmup=300&Preferences.MaxHealthyPercentage=110&Preferences.MinHealthyPercentage=50&Preferences.SkipMatching=true&Strategy=Rolling/).once
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

  describe '#latest_instance_refresh' do
    context 'when run as part of a deployment' do
      let(:template) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 1, 'MyLaunchTemplate') }

      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=StartInstanceRefresh&AutoScalingGroupName=test-asg/)
          .to_return(body: File.read('spec/support/stubs/StartInstanceRefresh.xml'))
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=DescribeInstanceRefreshes&AutoScalingGroupName=test-asg/)
          .to_return(body: File.read('spec/support/stubs/DescribeInstanceRefreshes.Pending.xml'))
        group.start_instance_refresh(template)
      end

      it 'returns status and percentage completed' do
        instance_refresh = group.latest_instance_refresh
        expect(instance_refresh.status).to eq('Pending')
        expect(instance_refresh.percentage_complete).to be_nil
        expect(instance_refresh.completed?).to be false
      end
    end

    context 'without a triggered refresh' do
      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=DescribeInstanceRefreshes&AutoScalingGroupName=test-asg/)
          .to_return(body: File.read('spec/support/stubs/DescribeInstanceRefreshes.InProgress.xml'))
      end

      it 'returns status and percentage completed' do
        instance_refresh = group.latest_instance_refresh
        expect(instance_refresh.status).to eq('InProgress')
        expect(instance_refresh.percentage_complete).to eq(25)
        expect(instance_refresh.completed?).to be false
        expect(instance_refresh.failed?).to be false
      end
    end

    context 'with a completed refresh' do
      let(:template) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 1, 'MyLaunchTemplate') }

      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=DescribeInstanceRefreshes&AutoScalingGroupName=test-asg/)
          .to_return(body: File.read('spec/support/stubs/DescribeInstanceRefreshes.Completed.xml'))
      end

      it 'returns status and percentage completed' do
        instance_refresh = group.latest_instance_refresh
        expect(instance_refresh.status).to eq('Successful')
        expect(instance_refresh.percentage_complete).to eq(100)
        expect(instance_refresh.completed?).to be true
        expect(instance_refresh.failed?).to be false
      end
    end

    context 'with a failed refresh' do
      let(:template) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 1, 'MyLaunchTemplate') }

      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=DescribeInstanceRefreshes&AutoScalingGroupName=test-asg/)
          .to_return(body: File.read('spec/support/stubs/DescribeInstanceRefreshes.Failed.xml'))
      end

      it 'returns status and percentage completed' do
        instance_refresh = group.latest_instance_refresh
        expect(instance_refresh.status).to eq('Failed')
        expect(instance_refresh.percentage_complete).to eq(50)
        expect(instance_refresh.completed?).to be true
        expect(instance_refresh.failed?).to be true
      end
    end

    context 'without any previous instance refreshes' do
      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=DescribeInstanceRefreshes&AutoScalingGroupName=test-asg/)
          .to_return(body: File.read('spec/support/stubs/DescribeInstanceRefreshes.Empty.xml'))
      end

      it 'returns nil' do
        instance_refresh = group.latest_instance_refresh
        expect(instance_refresh).to be_nil
      end
    end
  end
end
