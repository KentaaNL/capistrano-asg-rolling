# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # Singleton that holds the configuration and global state of the plugin.
      # State is eagerly initialized so accessors are lock-free.
      module Configuration
        extend Capistrano::DSL

        # Registered Auto Scaling Groups.
        @autoscale_groups = AutoscaleGroups.new

        # Launched Instances.
        @instances = Instances.new

        # Updated Launch Templates.
        @launch_templates = LaunchTemplates.new

        module_function

        def autoscale_groups
          @autoscale_groups
        end

        def instances
          @instances
        end

        def launch_templates
          @launch_templates
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

        def wait_for_instance_refresh?
          fetch(:asg_wait_for_instance_refresh, false)
        end

        def instance_refresh_polling_interval
          fetch(:asg_instance_refresh_polling_interval, 30)
        end

        def aws_retry_mode
          fetch(:asg_aws_retry_mode, 'adaptive')
        end

        def aws_retry_limit
          fetch(:asg_aws_retry_limit, 10)
        end

        def ami_wait_delay
          fetch(:asg_ami_wait_delay, 15)
        end

        def ami_wait_max_attempts
          fetch(:asg_ami_wait_max_attempts, 40)
        end
      end
    end
  end
end
