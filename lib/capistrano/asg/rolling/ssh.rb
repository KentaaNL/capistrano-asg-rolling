# frozen_string_literal: true

require 'time'

module Capistrano
  module ASG
    module Rolling
      # Test the SSHKit backend for availability.
      module SSH
        module_function

        WAIT_TIMEOUT = 300

        def wait_for_availability(backend)
          timeout = WAIT_TIMEOUT
          expires_at = Time.now + timeout

          loop do
            break if available?(backend)

            raise SSHAvailabilityTimeoutError, timeout if Time.now > expires_at

            sleep 1
          end
        end

        def available?(backend)
          backend.test('echo hello')

          true
        rescue ::Net::SSH::AuthenticationFailed, ::Net::SSH::Authentication::DisallowedMethod
          # SSH server is reachable and responding.
          true
        rescue ::Net::SSH::ConnectionTimeout, ::Net::SSH::Proxy::ConnectError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Errno::ECONNRESET
          # SSH server not reachable or port closed.
          false
        rescue ::Net::SSH::Disconnect # rubocop:disable Lint/DuplicateBranch
          # SSH server is reachable, but the connection dropped unexpectedly.
          false
        end
      end
    end
  end
end
