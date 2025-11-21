# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # SSH availability test.
      module SSH
        module_function

        def available?(ip_address, user, ssh_options)
          options = ssh_options || {}
          options[:timeout] = 10

          ::Net::SSH.start(ip_address, user, options) do |ssh|
            ssh.exec!('echo hello')
          end

          true
        rescue ::Net::SSH::AuthenticationFailed, ::Net::SSH::Authentication::DisallowedMethod
          # SSH server is reachable and responding.
          true
        rescue ::Net::SSH::ConnectionTimeout, ::Net::SSH::Proxy::ConnectError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT
          # SSH server not reachable or port closed.
          false
        end
      end
    end
  end
end
