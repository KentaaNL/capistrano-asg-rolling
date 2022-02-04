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
    end
  end
end
