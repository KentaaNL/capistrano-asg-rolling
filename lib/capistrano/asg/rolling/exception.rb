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

      class InstanceRefreshFailed < Capistrano::ASG::Rolling::Exception
      end

      # Exception when instance terminate fails.
      class InstanceTerminateFailed < Capistrano::ASG::Rolling::Exception
        attr_reader :instance

        def initialize(instance, exception)
          @instance = instance
          super(exception)
        end
      end
    end
  end
end
