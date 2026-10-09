# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # Colorized stdout/stderr output with optional timestamps and **bold** formatting.
      class Logger
        def initialize(timestamp: false, verbose: false)
          @timestamp = timestamp
          @verbose = verbose
        end

        def info(text)
          write($stdout, format_text(text))
        end

        def warning(text)
          write($stdout, format_text("WARNING: #{text}"))
        end

        def error(text)
          write($stderr, format_text(text, color: :red))
        end

        def verbose(text)
          info(text) if @verbose
        end

        private

        # Output may be gone (e.g. when called from at_exit); never let logging raise.
        def write(io, text)
          io.puts text
        rescue Errno::EPIPE, Errno::EIO, IOError
          nil
        end

        def format_text(text, color: nil)
          text = "[#{current_time}] #{text}" if @timestamp
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

        def current_time
          Time.now.strftime('%H:%M:%S')
        end
      end
    end
  end
end
