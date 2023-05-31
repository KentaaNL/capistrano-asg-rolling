# frozen_string_literal: true

require 'aws-sdk-autoscaling'

module Capistrano
  module ASG
    module Rolling
      # AWS EC2 Auto Scaling Group.
      class AutoscaleGroup
        include AWS

        LIFECYCLE_STATE_IN_SERVICE = 'InService'
        LIFECYCLE_STATE_STANDBY = 'Standby'

        attr_reader :name, :properties

        def initialize(name, properties = {})
          @name = name
          @properties = properties
        end

        def exists?
          aws_autoscaling_group.exists?
        end

        def launch_template
          @launch_template ||= begin
            template = aws_autoscaling_group.launch_template
            raise Capistrano::ASG::Rolling::NoLaunchTemplate if template.nil?

            LaunchTemplate.new(template.launch_template_id, template.version, template.launch_template_name)
          end
        end

        def subnet_ids
          aws_autoscaling_group.vpc_zone_identifier.split(',')
        end

        def instance_warmup_time
          aws_autoscaling_group.health_check_grace_period
        end

        def healthy_percentage
          properties.fetch(:healthy_percentage, 100)
        end

        def start_instance_refresh(launch_template)
          aws_autoscaling_client.start_instance_refresh(
            auto_scaling_group_name: name,
            strategy: 'Rolling',
            desired_configuration: {
              launch_template: {
                launch_template_id: launch_template.id,
                version: launch_template.version
              }
            },
            preferences: {
              instance_warmup: instance_warmup_time,
              min_healthy_percentage: healthy_percentage,
              skip_matching: true
            }
          )
        rescue Aws::AutoScaling::Errors::InstanceRefreshInProgress => e
          raise Capistrano::ASG::Rolling::InstanceRefreshFailed, e
        end

        # Returns instances with lifecycle state "InService" for this Auto Scaling Group.
        def instances
          instance_ids = aws_autoscaling_group.instances.select { |i| i.lifecycle_state == LIFECYCLE_STATE_IN_SERVICE }.map(&:instance_id)
          return [] if instance_ids.empty?

          response = aws_ec2_client.describe_instances(instance_ids: instance_ids)
          response.reservations.flat_map(&:instances).map do |instance|
            Instance.new(instance.instance_id, instance.private_ip_address, instance.public_ip_address, instance.image_id, self)
          end
        end

        def enter_standby(instance)
          instance = aws_autoscaling_group.instances.find { |i| i.id == instance.id }
          return if instance.nil?

          instance.enter_standby(should_decrement_desired_capacity: true)

          loop do
            instance.load
            break if instance.lifecycle_state == LIFECYCLE_STATE_STANDBY

            sleep 1
          end
        end

        def exit_standby(instance)
          instance = aws_autoscaling_group.instances.find { |i| i.id == instance.id }
          return if instance.nil?

          instance.exit_standby
        end

        def rolling?
          properties.fetch(:rolling, true)
        end

        def name_tag
          "Deployment for #{name}"
        end

        private

        def aws_autoscaling_group
          @aws_autoscaling_group ||= ::Aws::AutoScaling::AutoScalingGroup.new(name: name, client: aws_autoscaling_client)
        end
      end
    end
  end
end
