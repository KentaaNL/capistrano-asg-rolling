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

        def warning(text)
          $stdout.puts format_text("WARNING: #{text}")
        end

        def error(text)
          $stderr.puts format_text(text, color: :red) # rubocop:disable Style/StderrPuts
        end

        def verbose(text)
          info(text) if @verbose
        end

        private

        def format_text(text, color: nil)
          text = colorize_text(text, color) if color
          text.gsub(/\*\*(.+?)\*\*/, bold_text('\\1'))
        end

        def bold_text(text)
          "\e[1m#{text}\e[22m"
        end

        def colorize_text(text, color)
          _color.colorize(text, color)
        end

        def _color
          @_color ||= SSHKit::Color.new($stdout)
        end
      end
    end
  end
end
