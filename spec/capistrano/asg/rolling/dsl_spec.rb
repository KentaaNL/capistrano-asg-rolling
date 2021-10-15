# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::DSL do
  include described_class

  let(:config) { Capistrano::ASG::Rolling::Configuration }

  describe '#autoscale' do
    context 'with one auto scaling group' do
      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=DescribeAutoScalingGroups/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingGroups.xml'))
      end

      it 'adds the auto scaling group' do
        autoscale 'my-asg'

        expect(config.autoscale_groups.count).to eq 1
      end

      it 'adds the properties' do
        autoscale 'my-asg', user: 'deployer', roles: [:web]

        group = config.autoscale_groups.first
        expect(group).not_to be nil
        expect(group.name).to eq('my-asg')
        expect(group.properties).to include(:user, :roles)
      end
    end

    context 'without auto scaling groups' do
      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=DescribeAutoScalingGroups/).to_return(body: File.read('spec/support/stubs/DescribeAutoScalingGroups.Empty.xml'))
      end

      it 'raises an exception' do
        expect { autoscale 'my-asg' }.to raise_error(Capistrano::ASG::Rolling::NoAutoScalingGroup)
      end
    end
  end
end
