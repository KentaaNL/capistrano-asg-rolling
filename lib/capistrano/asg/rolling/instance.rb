# frozen_string_literal: true

require 'time'

module Capistrano
  module ASG
    module Rolling
      # AWS EC2 instance.
      class Instance
        include AWS

        attr_reader :id, :private_ip_address, :public_ip_address, :image_id, :autoscale_group
        attr_accessor :auto_terminate, :terminated
        alias auto_terminate? auto_terminate
        alias terminated? terminated

        def initialize(id, private_ip_address, public_ip_address, image_id, autoscale_group)
          @id = id
          @private_ip_address = private_ip_address
          @public_ip_address = public_ip_address
          @image_id = image_id
          @autoscale_group = autoscale_group
          @auto_terminate = true
          @terminated = false
        end

        # Launch a new instance based on settings from Auto Scaling Group and associated Launch Template.
        def self.run(autoscaling_group:, overrides: nil)
          launch_template = autoscaling_group.launch_template

          aws_ec2_client = autoscaling_group.aws_ec2_client
          options = {
            min_count: 1,
            max_count: 1,
            launch_template: {
              launch_template_id: launch_template.id,
              version: launch_template.version
            }
          }

          # Add a subnet defined in the Auto Scaling Group, but only when the Launch Template
          # does not define a network interface. Otherwise it will trigger the following error:
          # => Network interfaces and an instance-level subnet ID may not be specified on the same request
          options[:subnet_id] = autoscaling_group.subnet_ids.sample if launch_template.network_interfaces.empty?

          # Optionally override settings in the Launch Template.
          options.merge!(overrides) if overrides

          resource_tags = [
            { key: 'Name', value: autoscaling_group.name_tag }
          ]
          options[:tag_specifications] = [
            { resource_type: 'instance', tags: resource_tags },
            { resource_type: 'volume', tags: resource_tags }
          ]

          response = aws_ec2_client.run_instances(options)

          instance = response.instances.first

          # Wait until the instance is running and has a public IP address.
          aws_instance = ::Aws::EC2::Instance.new(instance.instance_id, client: aws_ec2_client)
          instance = aws_instance.wait_until_running

          new(instance.instance_id, instance.private_ip_address, instance.public_ip_address, instance.image_id, autoscaling_group)
        end

        def wait_for_ssh
          started_at = Time.now

          loop do
            result = SSH.test?(ip_address, autoscale_group.properties[:user], Configuration.ssh_options)

            break if result || Time.now - started_at > 300

            sleep 1
          end
        end

        def ip_address
          Configuration.use_private_ip_address? ? private_ip_address : public_ip_address
        end

        def stop
          aws_ec2_client.stop_instances(instance_ids: [id])
          aws_ec2_client.wait_until(:instance_stopped, instance_ids: [id])
        end

        def terminate(wait: false)
          aws_ec2_client.terminate_instances(instance_ids: [id])
          aws_ec2_client.wait_until(:instance_terminated, instance_ids: [id]) if wait

          @terminated = true
        end

        def create_ami(name: nil, description: nil, tags: nil)
          ami_tags = {
            'Name' => autoscale_group.name_tag,
            'capistrano-asg-rolling:version' => Capistrano::ASG::Rolling::VERSION
          }
          ami_tags.merge!(tags) if tags

          AMI.create(instance: self, name: name || ami_name, description: description, tags: ami_tags)
        end

        private

        def ami_name
          "#{autoscale_group.name_tag} on #{Time.now.strftime('%Y-%m-%d at %H.%M.%S')}"
        end
      end
    end
  end
end
