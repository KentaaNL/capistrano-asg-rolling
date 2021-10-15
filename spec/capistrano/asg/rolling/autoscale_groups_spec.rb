# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::AutoscaleGroups do
  subject(:groups) { described_class.new }

  let(:group1) { Capistrano::ASG::Rolling::AutoscaleGroup.new('asg-web', user: 'deployer') }
  let(:group2) { Capistrano::ASG::Rolling::AutoscaleGroup.new('asg-jobs', user: 'deployer') }

  before do
    groups << group1
    groups << group2
  end

  describe '#each' do
    it 'returns an Enumerator' do
      expect(groups.each).to be_a(Enumerator)
    end

    context 'without filter' do
      it 'returns all Auto Scaling Groups' do
        expect(groups.count).to eq(2)
      end
    end

    context 'with filter' do
      before do
        Capistrano::ASG::Rolling::Configuration.set(:asg_rolling_group_name, 'asg-jobs')
      end

      it 'returns filtered Auto Scaling Groups' do
        expect(groups.count).to eq(1)
        expect(groups.first.name).to eq('asg-jobs')
      end
    end
  end

  describe '#with_launch_template' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeAutoScalingGroups/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingGroups.xml'))
    end

    it 'returns an AutoscaleGroups object' do
      template = group1.launch_template
      expect(groups.with_launch_template(template)).to be_a(described_class)
    end

    it 'returns an empty set when launch template does not match' do
      template = Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 1)
      expect(groups.with_launch_template(template).count).to eq(0)
    end

    it 'returns auto scaling groups with the matching launch template' do
      template = group1.launch_template
      expect(groups.with_launch_template(template).count).to eq(2)
      expect(groups.with_launch_template(template)).to include(group1, group2)
    end
  end

  describe '#update_launch_templates' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeAutoScalingGroups/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingGroups.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeLaunchTemplateVersions/).to_return(body: File.read('spec/support/stubs/DescribeLaunchTemplateVersions.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=CreateLaunchTemplateVersion/).to_return(body: File.read('spec/support/stubs/CreateLaunchTemplateVersion.xml'))
    end

    let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345', '192.168.1.88', '54.194.252.215', 'ami-8c1be5f6', nil) }
    let(:ami) { Capistrano::ASG::Rolling::AMI.new('ami-12345', instance) }

    it 'calls the API to create a new launch template version' do
      groups.update_launch_templates(amis: [ami])
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=CreateLaunchTemplateVersion&LaunchTemplateData.ImageId=ami-12345&LaunchTemplateId=lt-0a20c965061f64abc&SourceVersion=1/).once
    end

    context 'when old AMI does not exist' do
      let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345', '192.168.1.88', '54.194.252.215', 'ami-67890', nil) }

      it 'does not call the API' do
        groups.update_launch_templates(amis: [ami])
        expect(WebMock).not_to have_requested(:post, /amazonaws.com/).with(body: /Action=CreateLaunchTemplateVersion/)
      end
    end

    context 'when Instance has no AMI' do
      let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345', '192.168.1.88', '54.194.252.215', nil, nil) }

      it 'does not call the API' do
        groups.update_launch_templates(amis: [ami])
        expect(WebMock).not_to have_requested(:post, /amazonaws.com/).with(body: /Action=CreateLaunchTemplateVersion/)
      end
    end

    it 'returns the new launch template versions' do
      launch_templates = groups.update_launch_templates(amis: [ami])
      expect(launch_templates).not_to be_empty

      version = launch_templates.first
      expect(version.id).to eq('lt-0a20c965061f6454a')
      expect(version.version).to eq('4')
    end
  end

  describe '#start_instance_refresh' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeAutoScalingGroups/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingGroups.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=StartInstanceRefresh/).to_return(body: File.read('spec/support/stubs/StartInstanceRefresh.xml'))
    end

    it 'starts instance refresh for all auto scaling groups' do
      groups.start_instance_refresh
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=StartInstanceRefresh&AutoScalingGroupName=asg-web/).once
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=StartInstanceRefresh&AutoScalingGroupName=asg-jobs/).once
    end
  end
end
