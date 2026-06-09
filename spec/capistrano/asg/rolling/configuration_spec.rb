# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::Configuration do
  describe '.autoscale_groups' do
    it 'returns an AutoscaleGroups instance' do
      expect(described_class.autoscale_groups).to be_a(Capistrano::ASG::Rolling::AutoscaleGroups)
    end
  end

  describe '.instances' do
    it 'returns an Instances instance' do
      expect(described_class.instances).to be_a(Capistrano::ASG::Rolling::Instances)
    end
  end

  describe '.launch_templates' do
    it 'returns a LaunchTemplates instance' do
      expect(described_class.launch_templates).to be_a(Capistrano::ASG::Rolling::LaunchTemplates)
    end
  end

  describe '.reset!' do
    before do
      described_class.autoscale_groups << Capistrano::ASG::Rolling::AutoscaleGroup.new('asg-web')
      described_class.instances << Capistrano::ASG::Rolling::Instance.new('i-12345', nil, nil, nil, nil)
      described_class.launch_templates << Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 1, 'MyLaunchTemplate')
    end

    it 'clears autoscale_groups' do
      described_class.reset!
      expect(described_class.autoscale_groups).to be_a(Capistrano::ASG::Rolling::AutoscaleGroups)
      expect(described_class.autoscale_groups).to be_empty
    end

    it 'clears instances' do
      described_class.reset!
      expect(described_class.instances).to be_a(Capistrano::ASG::Rolling::Instances)
      expect(described_class.instances).to be_empty
    end

    it 'clears launch_templates' do
      described_class.reset!
      expect(described_class.launch_templates).to be_a(Capistrano::ASG::Rolling::LaunchTemplates)
      expect(described_class.launch_templates).to be_empty
    end
  end
end
