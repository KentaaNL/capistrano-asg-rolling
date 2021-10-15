# frozen_string_literal: true

require 'aws-sdk-autoscaling'
require 'aws-sdk-ec2'

module Capistrano
  module ASG
    module Rolling
      # AWS SDK.
      module AWS
        def aws_autoscaling_client
          @aws_autoscaling_client ||= ::Aws::AutoScaling::Client.new(aws_options)
        end

        def aws_ec2_client
          @aws_ec2_client ||= ::Aws::EC2::Client.new(aws_options)
        end

        private

        def aws_options
          options = {}
          options[:region] = aws_region if aws_region
          options[:credentials] = aws_credentials if aws_credentials.set?
          options[:http_wire_trace] = true if ENV['AWS_HTTP_WIRE_TRACE'] == '1'
          options
        end

        def aws_credentials
          ::Aws::Credentials.new(aws_access_key_id, aws_secret_access_key)
        end

        def aws_access_key_id
          Configuration.aws_access_key_id
        end

        def aws_secret_access_key
          Configuration.aws_secret_access_key
        end

        def aws_region
          Configuration.aws_region
        end
      end
    end
  end
end
