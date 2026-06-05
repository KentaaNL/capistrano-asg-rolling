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

        # For each AMI, find templates still pointing at the old image it was built
        # from, then create new template versions referencing the new AMI in parallel.
        #
        # Returns `LaunchTemplates` containing only the newly created versions.
        def update(amis:, description: nil)
          template_image_pairs = amis.flat_map do |ami|
            old_image_id = ami.instance.image_id
            new_image_id = ami.id

            with_image(old_image_id).map { |template| [template, new_image_id] }
          end

          updated_templates = Parallel.run(template_image_pairs) do |template, new_image_id|
            template.create_version(image_id: new_image_id, description: description)
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
