# frozen_string_literal: true

ENV['AWS_ACCESS_KEY_ID'] = 'test'
ENV['AWS_SECRET_ACCESS_KEY'] = 'test'
ENV['AWS_REGION'] = 'eu-west-1'

# Force SSHKit to output ANSI colors.
ENV['SSHKIT_COLOR'] = '1'

require 'bundler/setup'
require 'capistrano/asg/rolling'

require 'webmock/rspec'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Reset configuration to the default state before running each spec.
  config.before do
    Capistrano::ASG::Rolling::Configuration.instance_variable_set(:@autoscale_groups, nil)
    Capistrano::ASG::Rolling::Configuration.instance_variable_set(:@instances, nil)
    Capistrano::ASG::Rolling::Configuration.instance_variable_set(:@launch_templates, nil)

    Capistrano::ASG::Rolling::Configuration.set(:asg_rolling_group_name, nil)
    Capistrano::ASG::Rolling::Configuration.set(:asg_rolling_use_private_ip_address, true)

    Capistrano::ASG::Rolling::Configuration.set(:application, 'rspec-application')
    Capistrano::ASG::Rolling::Configuration.set(:stage, 'test')

    Capistrano::ASG::Rolling::Configuration.set(:branch, 'feature-x')
    Capistrano::ASG::Rolling::Configuration.set(:local_user, 'deployer')
    Capistrano::ASG::Rolling::Configuration.set(:current_revision, 'abcd1234')
    Capistrano::ASG::Rolling::Configuration.set(:release_timestamp, '20241004124200')
  end
end
