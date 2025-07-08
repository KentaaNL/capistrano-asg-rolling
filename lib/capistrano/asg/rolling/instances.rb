# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # Collection of Instances. Runs commands on instances in parallel.
      class Instances
        include Enumerable

        def initialize(instances = [])
          @instances = instances
        end

        def <<(instance)
          @instances << instance
        end

        def each(&)
          instances.each(&)
        end

        def empty?
          instances.empty?
        end

        def auto_terminate
          self.class.new(select(&:auto_terminate?))
        end

        def with_image(image_id)
          self.class.new(select { |instance| instance.image_id == image_id })
        end

        def wait_for_ssh
          Parallel.run(instances, &:wait_for_ssh)
        end

        def stop
          Parallel.run(instances, &:stop)
        end

        def terminate
          Parallel.run(instances, &:terminate)
        end

        def create_ami(name: nil, description: nil, tags: nil)
          Parallel.run(instances) do |instance|
            instance.create_ami(name: name, description: description, tags: tags)
          end
        end

        private

        def instances
          @instances.reject(&:terminated?)
        end
      end
    end
  end
end
