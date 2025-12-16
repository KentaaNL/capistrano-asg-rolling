# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # Base class for exceptions.
      class Exception < StandardError
      end

      class NoAutoScalingGroup < Capistrano::ASG::Rolling::Exception
      end

      class NoLaunchTemplate < Capistrano::ASG::Rolling::Exception
      end

      class StartInstanceRefreshError < Capistrano::ASG::Rolling::Exception
      end

      # Exception when the instance refresh failed on one of the ASGs.
      class InstanceRefreshFailed < Capistrano::ASG::Rolling::Exception
        def initialize
          super('Failed to update Auto Scaling Group(s)')
        end
      end

      # Exception when instance terminate has failed.
      class InstanceTerminateFailed < Capistrano::ASG::Rolling::Exception
        attr_reader :instance

        def initialize(instance, exception)
          @instance = instance
          super(exception)
        end
      end

      # Exception when no instances could be launched.
      class NoInstancesLaunched < Capistrano::ASG::Rolling::Exception
        def initialize
          super('No instances have been launched. Are you using a configuration with rolling deployments?')
        end
      end

      # Exception when waiting for SSH availability timed out.
      class SSHAvailabilityTimeoutError < Capistrano::ASG::Rolling::Exception
        def initialize(timeout)
          super("Timed out waiting for SSH to become available after #{timeout} seconds")
        end
      end
    end
  end
end
