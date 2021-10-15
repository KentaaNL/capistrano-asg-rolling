# frozen_string_literal: true

# Load DSL and set up stages
require 'capistrano/setup'

# Include default deployment tasks
require 'capistrano/deploy'

RSpec.describe Capistrano::ASG::Rolling::Plugin do
  include Capistrano::DSL

  it 'defines tasks when constructed' do
    install_plugin described_class

    expect(Rake::Task['rolling:setup']).not_to be nil
    expect(Rake::Task['rolling:update']).not_to be nil
    expect(Rake::Task['rolling:cleanup']).not_to be nil
    expect(Rake::Task['rolling:launch_instances']).not_to be nil
    expect(Rake::Task['rolling:create_ami']).not_to be nil
  end
end
