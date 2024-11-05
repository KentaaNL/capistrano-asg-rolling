# frozen_string_literal: true

# Load DSL and set up stages
require 'capistrano/setup'

# Include default deployment tasks
require 'capistrano/deploy'

RSpec.describe Capistrano::ASG::Rolling::Tags do
  describe '#ami_tags' do
    it 'returns a hash with tags to add to an AMI' do
      expect(described_class.ami_tags).to eq(
        'capistrano-asg-rolling:application' => 'rspec-application',
        'capistrano-asg-rolling:stage' => 'test',
        'capistrano-asg-rolling:deployment-branch' => 'feature-x',
        'capistrano-asg-rolling:deployment-release' => '20241004124200',
        'capistrano-asg-rolling:deployment-revision' => 'abcd1234',
        'capistrano-asg-rolling:deployment-user' => 'deployer',
        'capistrano-asg-rolling:gem-version' => Capistrano::ASG::Rolling::VERSION
      )
    end
  end

  describe '#application_tags' do
    it 'returns a hash with tags for this application' do
      expect(described_class.application_tags).to eq(
        'capistrano-asg-rolling:application' => 'rspec-application',
        'capistrano-asg-rolling:stage' => 'test'
      )
    end
  end

  describe '#deployment_tags' do
    it 'returns a hash with tags for this deployment' do
      expect(described_class.deployment_tags).to eq(
        'capistrano-asg-rolling:deployment-branch' => 'feature-x',
        'capistrano-asg-rolling:deployment-release' => '20241004124200',
        'capistrano-asg-rolling:deployment-revision' => 'abcd1234',
        'capistrano-asg-rolling:deployment-user' => 'deployer'
      )
    end
  end

  describe '#gem_tags' do
    it 'returns a hash with tags for this gem' do
      expect(described_class.gem_tags).to eq(
        'capistrano-asg-rolling:gem-version' => Capistrano::ASG::Rolling::VERSION
      )
    end
  end

  describe '#custom_tags' do
    before { Capistrano::ASG::Rolling::Configuration.set(:asg_rolling_ami_tags, { 'custom-tag' => 'foobar' }) }

    it 'returns a hash with custom tags' do
      expect(described_class.custom_tags).to eq(
        'custom-tag' => 'foobar'
      )
    end
  end
end
