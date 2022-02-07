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

  describe '#launch_templates' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeAutoScalingGroups/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingGroups.xml'))
    end

    it 'returns a LaunchTemplates object' do
      expect(groups.launch_templates).to be_a(Capistrano::ASG::Rolling::LaunchTemplates)
    end

    it 'includes the launch templates from all ASGs' do
      template1 = group1.launch_template
      template2 = group2.launch_template
      expect(groups.launch_templates).to include(template1, template2)
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
      template = Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 1, 'MyLaunchTemplate')
      expect(groups.with_launch_template(template).count).to eq(0)
    end

    it 'returns auto scaling groups with the matching launch template' do
      template = group1.launch_template
      expect(groups.with_launch_template(template).count).to eq(2)
      expect(groups.with_launch_template(template)).to include(group1, group2)
    end
  end
end
