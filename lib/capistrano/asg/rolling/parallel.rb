# frozen_string_literal: true

require 'concurrent/array'

module Capistrano
  module ASG
    module Rolling
      # Simple helper for running code in parallel.
      module Parallel
        module_function

        def run(work)
          result = Concurrent::Array.new
          threads = []

          work.each do |w|
            threads << Thread.new do
              result << yield(w)
            end
          end

          threads.each(&:join)

          result
        end
      end
    end
  end
end
