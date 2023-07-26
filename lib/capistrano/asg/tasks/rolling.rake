# frozen_string_literal: true

namespace :rolling do
  desc 'Setup servers to be used for (rolling) deployment'
  task :setup do
    config.autoscale_groups.each do |group|
      if group.rolling?
        logger.info "Auto Scaling Group: **#{group.name}**, rolling deployment strategy."

        # If we've already launched an instance with this image, then skip it.
        next unless config.instances.with_image(group.launch_template.image_id).empty?

        instance = Capistrano::ASG::Rolling::Instance.run(autoscaling_group: group, overrides: config.instance_overrides)
        logger.info "Launched Instance: **#{instance.id}**"
        config.instances << instance

        logger.verbose "Adding server: **#{instance.ip_address}**"

        # Add server to the Capistrano server list.
        server(instance.ip_address, group.properties)
      else
        logger.info "Auto Scaling Group: **#{group.name}**, standard deployment strategy."

        group.instances.each_with_index do |instance, index| # rubocop:disable Lint/ShadowingOuterLocalVariable
          if index.zero? && group.properties.key?(:primary_roles)
            server_properties = group.properties.dup
            server_properties[:roles] = server_properties.delete(:primary_roles)
          else
            server_properties = group.properties
          end

          logger.verbose "Adding server: **#{instance.ip_address}**"

          # Add server to the Capistrano server list.
          server(instance.ip_address, server_properties)
        end
      end
    end

    unless config.instances.empty?
      logger.info 'Waiting for SSH to be available...'
      config.instances.wait_for_ssh
    end
  end

  desc 'Update Auto Scaling Groups: create AMIs, update Launch Templates and start Instance Refresh'
  task :update do
    if config.rolling_update? && !config.instances.empty?
      logger.info 'Stopping instance(s)...'
      config.instances.stop

      logger.info 'Creating AMI(s)...'
      amis = config.instances.create_ami(description: revision_log_message)

      logger.info 'Updating Launch Template(s) with the new AMI(s)...'
      launch_templates = config.autoscale_groups.launch_templates
      updated_templates = launch_templates.update(amis: amis, description: revision_log_message)

      logger.info 'Triggering Instance Refresh on Auto Scaling Group(s)...'
      updated_templates.each do |launch_template|
        config.autoscale_groups.with_launch_template(launch_template).each do |group|
          group.start_instance_refresh(launch_template)

          logger.verbose "Successfully started Instance Refresh on Auto Scaling Group **#{group.name}**."
        rescue Capistrano::ASG::Rolling::InstanceRefreshFailed => e
          logger.info "Failed to start Instance Refresh on Auto Scaling Group **#{group.name}**: #{e.message}"
        end
      end

      config.launch_templates.merge(updated_templates)
    end
  end

  desc 'Clean up old Launch Template versions and AMIs and terminate instances'
  task :cleanup do
    unless config.launch_templates.empty?
      # Keep track of deleted AMIs, so we can clean up Launch Templates that use the same AMI.
      deleted_amis = []

      logger.info 'Cleaning up old Launch Template version(s) and AMI(s)...'
      config.launch_templates.each do |launch_template|
        launch_template.previous_versions.reject(&:default_version?).drop(config.keep_versions).each do |version|
          # Need to retrieve AMI before deleting the Launch Template version.
          ami = version.ami
          exists = ami.exists?
          deleted = deleted_amis.include?(ami)

          if !exists && !deleted
            logger.info("WARNING: AMI **#{ami.id}** does not exist for Launch Template **#{version.name}** version **#{version.version}**.")
            next
          end

          # Only clean up when AMI was tagged by us.
          next if exists && !ami.tag?('capistrano-asg-rolling:version')

          logger.verbose "Deleting Launch Template **#{version.name}** version **#{version.version}**..."
          version.delete

          next if deleted

          logger.verbose "Deleting AMI **#{ami.id}** and snapshots..."
          ami.delete

          deleted_amis << ami
        end
      end
    end

    begin
      instances = config.instances.auto_terminate
      if instances.any?
        logger.info 'Terminating instance(s)...'
        instances.terminate
      end
    rescue Aws::Errors::ServiceError => e
      logger.warning "Error deleting instance: #{e}"
    end
    invoke 'rolling:instance_refresh_status' if fetch(:asg_wait_for_instance_refresh)
  end

  desc 'Launch Instances by marking instances to not automatically terminate'
  task :launch_instances do
    if config.instances.any?
      config.instances.each do |instance|
        instance.auto_terminate = false
      end
    else
      logger.error 'No instances have been launched. Are you using a configuration with rolling deployments?'
      exit 1
    end
  end

  desc 'Do a test deployment: run the deploy task but do not trigger the update ASG task and do not automatically terminate instances'
  task :deploy_test do
    config.rolling_update = false

    if config.instances.any?
      config.instances.each do |instance|
        instance.auto_terminate = false
      end
    else
      logger.error 'No instances have been launched. Are you using a configuration with rolling deployments?'
      exit 1
    end

    invoke 'deploy'
  end

  desc 'Create an AMI from an Instance in the Auto Scaling Groups'
  task :create_ami do
    config.autoscale_groups.each do |group|
      logger.info 'Selecting instance to create AMI from...'

      # Pick a random instance, put it in standby and create an AMI.
      instance = group.instances.sample
      if instance
        logger.info "Instance **#{instance.id}** entering standby state..."
        group.enter_standby(instance)

        logger.info 'Creating AMI...'
        ami = instance.create_ami(description: revision_log_message)

        logger.info "Instance **#{instance.id}** exiting standby state..."
        group.exit_standby(instance)

        logger.info 'Updating Launch Template with the new AMI...'
        launch_template = group.launch_template
        launch_template.create_version(image_id: ami.id, description: revision_log_message)

        config.launch_templates << launch_template
      else
        logger.error 'Unable to create AMI. No instance with a valid state was found in the Auto Scaling Group.'
      end
    end
  end

  desc 'Get status of instance refresh'
  task :instance_refresh_status do
    groups = {}
    config.autoscale_groups.each { |group| groups[group.name] = group }
    while groups.count.positive?
      groups.each do |name, group|
        refresh = group.latest_instance_refresh
        status = refresh[:status]
        percentage_complete = refresh[:percentage_complete]
        refresh_completed = Capistrano::ASG::Rolling::AutoscaleGroup::COMPLETED_REFRESH_STATUSES.include?(status)
        if refresh.nil? || refresh_completed == true
          logger.info "Auto Scaling Group: **#{name}**, completed with status '#{status}'"
          groups.delete(name)
        elsif !percentage_complete.nil?
          logger.info "Auto Scaling Group: **#{name}**, #{percentage_complete}% completed, #{status}"
        else
          logger.info "Auto Scaling Group: **#{name}**, status '#{status}'"
        end
      end
      if groups.count.positive?
        wait_for = fetch(:asg_instance_refresh_polling_interval, 30)
        logger.info "Instance refresh(es) not completed, waiting #{wait_for} seconds"
        sleep wait_for
      end
    end
  end
end
