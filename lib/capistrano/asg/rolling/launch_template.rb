# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # AWS EC2 Launch Template.
      class LaunchTemplate
        include AWS

        attr_reader :id, :version, :name, :default_version
        alias default_version? default_version

        def initialize(id, version, name, default_version: false)
          @id = id
          @version = version.to_s
          @name = name
          @default_version = default_version
        end

        def create_version(image_id:, description: nil)
          response = aws_ec2_client.create_launch_template_version(
            launch_template_data: { image_id: image_id },
            launch_template_id: id,
            source_version: version,
            version_description: description
          )
          version = response.launch_template_version

          self.class.new(version.launch_template_id, version.version_number, version.launch_template_name, default_version: version.default_version)
        end

        def delete
          aws_ec2_client.delete_launch_template_versions(
            launch_template_id: id,
            versions: [version]
          )
        end

        def ami
          @ami ||= AMI.new(image_id)
        end

        def previous_versions
          aws_ec2_client.describe_launch_template_versions(launch_template_id: id)
                        .launch_template_versions
                        .sort_by { |v| -v.version_number }
                        .select { |v| v.version_number < version_number }
                        .map { |v| self.class.new(v.launch_template_id, v.version_number, v.launch_template_name, default_version: v.default_version) }
        end

        def version_number
          aws_describe_launch_template_version.version_number
        end

        def image_id
          aws_describe_launch_template_version.launch_template_data.image_id
        end

        def network_interfaces
          aws_describe_launch_template_version.launch_template_data.network_interfaces
        end

        def security_group_ids
          aws_describe_launch_template_version.launch_template_data.security_group_ids
        end

        # Object equality for Launch Templates is only by ID. Version number is deliberately not taken in account.
        def ==(other)
          id == other.id
        end

        alias eql? ==

        def hash
          id.hash
        end

        private

        def aws_describe_launch_template_version
          @aws_describe_launch_template_version ||=
            aws_ec2_client.describe_launch_template_versions(launch_template_id: id, versions: [version])
                          .launch_template_versions.first
        end
      end
    end
  end
end
