# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # Collection of Auto Scaling Groups.
      class AutoscaleGroups
        include Enumerable

        def initialize(groups = [])
          @groups = groups
        end

        def <<(group)
          @groups << group
        end

        def each(&block)
          @groups.reject { |group| filtered?(group) }.each(&block)
        end

        def launch_templates
          templates = @groups.map(&:launch_template)
          LaunchTemplates.new(templates)
        end

        def with_launch_template(launch_template)
          self.class.new(select { |group| group.launch_template == launch_template })
        end

        private

        def filtered?(group)
          return false if Configuration.auto_scaling_group_name.nil?

          Configuration.auto_scaling_group_name != group.name
        end
      end
    end
  end
end
