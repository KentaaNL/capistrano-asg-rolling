# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # SSH availability test.
      module SSH
        module_function

        def test?(ip_address, user, ssh_options)
          options = ssh_options || {}
          options[:timeout] = 10

          ::Net::SSH.start(ip_address, user, options) do |ssh|
            ssh.exec!('echo hello')
          end

          true
        rescue ::Net::SSH::ConnectionTimeout, ::Net::SSH::Proxy::ConnectError, Errno::ECONNREFUSED, Errno::ETIMEDOUT
          false
        end
      end
    end
  end
end
