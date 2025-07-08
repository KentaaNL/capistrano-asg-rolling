# frozen_string_literal: true

require 'set'

module Capistrano
  module ASG
    module Rolling
      # Collection of Launch Templates.
      class LaunchTemplates
        include Enumerable

        def initialize(templates = [])
          @templates = Set.new(templates)
        end

        def <<(template)
          @templates << template
        end

        def merge(templates)
          @templates.merge(templates)
        end

        def each(&)
          @templates.each(&)
        end

        def empty?
          @templates.empty?
        end

        def update(amis:, description: nil)
          updated_templates = []

          amis.each do |ami|
            old_image_id = ami.instance.image_id
            new_image_id = ami.id

            with_image(old_image_id).each do |template|
              updated_templates << template.create_version(image_id: new_image_id, description: description)
            end
          end

          self.class.new(updated_templates)
        end

        private

        def with_image(image_id)
          self.class.new(select { |template| template.image_id == image_id })
        end
      end
    end
  end
end
