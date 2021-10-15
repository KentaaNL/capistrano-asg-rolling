# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # Adds the autoscale DSL to the Capistrano configuration:
      #
      # autoscale 'my-asg', user: 'deployer', roles: %w(app assets)
      #
      module DSL
        def autoscale(name, properties = {})
          group = Capistrano::ASG::Rolling::AutoscaleGroup.new(name, properties)
          raise Capistrano::ASG::Rolling::NoAutoScalingGroup, "Auto Scaling Group #{name} could not be found." unless group.exists?

          Capistrano::ASG::Rolling::Configuration.autoscale_groups << group
        end
      end
    end
  end
end

extend Capistrano::ASG::Rolling::DSL # rubocop:disable Style/MixinUsage
