# frozen_string_literal: true

# Load DSL and set up stages
require 'capistrano/setup'

# Include default deployment tasks
require 'capistrano/deploy'

RSpec.describe Capistrano::ASG::Rolling::Plugin do
  include Capistrano::DSL

  it 'defines tasks when constructed #1' do
    install_plugin described_class

    expect(Rake::Task['rolling:setup']).not_to be_nil
    expect(Rake::Task['rolling:update']).not_to be_nil
    expect(Rake::Task['rolling:cleanup']).not_to be_nil
  end

  it 'defines tasks when constructed #2' do
    install_plugin described_class

    expect(Rake::Task['rolling:launch_instances']).not_to be_nil
    expect(Rake::Task['rolling:create_ami']).not_to be_nil
    expect(Rake::Task['rolling:instance_refresh_status']).not_to be_nil
  end

  describe '#config' do
    it 'exposes the config helper' do
      plugin = described_class.new
      expect(plugin.config).to eq(Capistrano::ASG::Rolling::Configuration)
    end
  end

  describe '#logger' do
    it 'exposes the logger class' do
      plugin = described_class.new
      expect(plugin.logger).to be_a(Capistrano::ASG::Rolling::Logger)
    end
  end
end
