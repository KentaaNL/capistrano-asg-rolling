# frozen_string_literal: true

require 'concurrent/array'

module Capistrano
  module ASG
    module Rolling
      # Simple helper for running code in parallel.
      module Parallel
        module_function

        # Runs the given block once per element of `work`, in parallel.
        #
        # All threads are joined before this method returns, so a failure in one
        # block does not abandon the other in-flight threads. If any block
        # raises, the first error is re-raised after all threads have completed;
        # additional errors are surfaced via `Kernel.warn`.
        def run(work)
          results = Concurrent::Array.new
          errors = Concurrent::Array.new

          threads = work.map do |w|
            Thread.new do
              results << yield(w)
            rescue StandardError => e
              errors << e
            end
          end

          threads.each(&:join)

          if errors.any?
            errors.drop(1).each do |e|
              Kernel.warn("WARNING: parallel task failed: #{e.class}: #{e.message}")
            end
            raise errors.first
          end

          results
        end
      end
    end
  end
end
