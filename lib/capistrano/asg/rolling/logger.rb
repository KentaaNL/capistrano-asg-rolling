# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # Logging support.
      class Logger
        def initialize(verbose: false)
          @verbose = verbose
        end

        def info(text)
          $stdout.puts format_text(text)
        end

        def error(text)
          $stderr.puts color(format_text(text), :red) # rubocop:disable Style/StderrPuts
        end

        def verbose(text)
          info(text) if @verbose
        end

        def bold(text, color = :light_white)
          color(text, color, :bold)
        end

        def color(text, color, mode = nil)
          _color.colorize(text, color, mode)
        end

        private

        def format_text(text)
          text.gsub(/\*\*(.+?)\*\*/, bold('\\1'))
        end

        def _color
          @_color ||= SSHKit::Color.new($stdout)
        end
      end
    end
  end
end
