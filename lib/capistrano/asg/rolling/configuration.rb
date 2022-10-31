# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # Singleton that holds the configuration.
      module Configuration
        extend Capistrano::DSL

        module_function

        # Registered Auto Scaling Groups.
        def autoscale_groups
          @autoscale_groups ||= AutoscaleGroups.new
        end

        # Launched Instances.
        def instances
          @instances ||= Instances.new
        end

        # Updated Launch Templates.
        def launch_templates
          @launch_templates ||= LaunchTemplates.new
        end

        def aws_access_key_id
          fetch(:aws_access_key_id)
        end

        def aws_secret_access_key
          fetch(:aws_secret_access_key)
        end

        def aws_session_token
          fetch(:aws_session_token)
        end

        def aws_region
          fetch(:aws_region)
        end

        def auto_scaling_group_name
          fetch(:asg_rolling_group_name)
        end

        def ssh_options
          fetch(:asg_rolling_ssh_options, fetch(:ssh_options))
        end

        def instance_overrides
          fetch(:asg_rolling_instance_overrides)
        end

        def use_private_ip_address?
          fetch(:asg_rolling_use_private_ip_address)
        end

        def keep_versions
          fetch(:asg_rolling_keep_versions, fetch(:keep_releases))
        end

        def verbose?
          fetch(:asg_rolling_verbose)
        end

        def rolling_update=(value)
          set(:asg_rolling_update, value)
        end

        def rolling_update?
          fetch(:asg_rolling_update)
        end
      end
    end
  end
end
