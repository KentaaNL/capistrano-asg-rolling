# frozen_string_literal: true

require 'capistrano/plugin'

module Capistrano
  module ASG
    module Rolling
      # Load this Capistrano Plugin in your Capfile:
      #
      # require 'capistrano/asg/rolling'
      # install_plugin Capistrano::ASG::Rolling::Plugin
      #
      class Plugin < Capistrano::Plugin
        def set_defaults
          set_if_empty :asg_rolling_group_name, ENV.fetch('asg_name', nil)
          set_if_empty :asg_rolling_use_private_ip_address, true
          set_if_empty :asg_rolling_verbose, true
          set_if_empty :asg_rolling_update, true
        end

        def register_hooks
          Capistrano::DSL.stages.each do |stage|
            after stage, 'rolling:setup'
          end

          after 'deploy', 'rolling:update'
          after 'deploy:failed', 'rolling:cleanup'

          after 'rolling:update', 'rolling:cleanup'
          after 'rolling:create_ami', 'rolling:cleanup'
          after 'rolling:update', 'rolling:instance_refresh_status'
          after 'rolling:trigger_instance_refresh', 'rolling:instance_refresh_status'

          # Register an exit hook to do some cleanup when Capistrano
          # terminates without calling our after cleanup hook.
          at_exit { cleanup }
        end

        def define_tasks
          eval_rakefile File.expand_path('../tasks/rolling.rake', __dir__)
        end

        def logger
          @logger ||= Logger.new(verbose: config.verbose?)
        end

        def config
          Capistrano::ASG::Rolling::Configuration
        end

        def cleanup
          instances = config.instances.auto_terminate
          return if instances.empty?

          logger.info 'Terminating instance(s)...'
          instances.terminate
        rescue Capistrano::ASG::Rolling::InstanceTerminateFailed => e
          logger.warning "Failed to terminate Instance **#{e.instance.id}**: #{e.message}"
        end
      end
    end
  end
end
