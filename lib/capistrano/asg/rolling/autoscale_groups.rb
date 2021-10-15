# frozen_string_literal: true

require 'set'

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

        def with_launch_template(launch_template)
          self.class.new(select { |group| group.launch_template == launch_template })
        end

        def update_launch_templates(amis:, description: nil)
          launch_templates = Set.new

          amis.each do |ami|
            old_image_id = ami.instance.image_id
            new_image_id = ami.id

            find_launch_templates_for(image_id: old_image_id).each do |launch_template|
              launch_templates << launch_template.create_version(image_id: new_image_id, description: description)
            end
          end

          launch_templates
        end

        def start_instance_refresh
          each(&:start_instance_refresh)
        end

        private

        def filtered?(group)
          return false if Configuration.auto_scaling_group_name.nil?

          Configuration.auto_scaling_group_name != group.name
        end

        def find_launch_templates_for(image_id:)
          launch_templates = Set.new

          each do |group|
            launch_template = group.launch_template
            next if launch_template.image_id != image_id

            launch_templates << launch_template
          end

          launch_templates
        end
      end
    end
  end
end
