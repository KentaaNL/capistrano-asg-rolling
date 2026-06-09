# frozen_string_literal: true

namespace :rolling do
  desc 'Setup servers to be used for (rolling) deployment'
  task setup: %w[rolling:prepare rolling:wait_for_ssh]

  desc 'Resolve Auto Scaling Groups, launch rolling instances, and register all servers'
  task :prepare do
    rolling_groups = config.autoscale_groups.rolling
    if rolling_groups.any?
      rolling_groups.each do |group|
        logger.info "Auto Scaling Group: **#{group.name}**, rolling deployment strategy."
      end

      launched_instances = Capistrano::ASG::Rolling::Parallel.run(rolling_groups.with_unique_images) do |group|
        Capistrano::ASG::Rolling::Instance.run(
          autoscaling_group: group,
          overrides: config.instance_overrides
        ).tap { |instance| config.instances << instance }
      end

      launched_instances.each do |instance|
        logger.info "Launched Instance: **#{instance.id}**"

        group = instance.autoscale_group
        add_instance(instance, group.properties)
      end
    end

    standard_groups = config.autoscale_groups.standard
    standard_groups.each do |group|
      logger.info "Auto Scaling Group: **#{group.name}**, standard deployment strategy."

      group.instances.each_with_index do |instance, index|
        server_properties =
          if index.zero? && group.properties.key?(:primary_roles)
            group.properties.merge(roles: group.properties[:primary_roles]).except(:primary_roles)
          else
            group.properties
          end

        add_instance(instance, server_properties)
      end
    end
  end

  desc 'Wait for SSH to become available on launched instances'
  task :wait_for_ssh do
    unless config.instances.empty?
      logger.info 'Waiting for SSH to be available...'

      on roles(:all) do
        Capistrano::ASG::Rolling::SSH.wait_for_availability(self)
      end
    end
  end

  desc 'Update Auto Scaling Groups: create AMIs, update Launch Templates and start Instance Refresh'
  task :update do
    if config.rolling_update? && !config.instances.empty?
      logger.info 'Stopping instance(s)...'
      config.instances.stop

      logger.info 'Creating AMI(s)...'
      amis = config.instances.create_ami(description: revision_log_message, tags: Capistrano::ASG::Rolling::Tags.ami_tags)

      logger.info 'Updating Launch Template(s) with the new AMI(s)...'
      launch_templates = config.autoscale_groups.launch_templates
      updated_templates = launch_templates.update(amis: amis, description: revision_log_message)

      logger.info 'Triggering Instance Refresh on Auto Scaling Group(s)...'
      updated_templates.each do |launch_template|
        config.autoscale_groups.with_launch_template(launch_template).each do |group|
          group.start_instance_refresh(launch_template)

          logger.verbose "Successfully started Instance Refresh on Auto Scaling Group **#{group.name}**."
        rescue Capistrano::ASG::Rolling::StartInstanceRefreshError => e
          logger.warning "Failed to start Instance Refresh on Auto Scaling Group **#{group.name}**: #{e.message}"
        end
      end

      config.launch_templates.merge(updated_templates)
    end
  end

  desc 'Trigger instance refresh of deployed Auto Scaling Groups'
  task :trigger_instance_refresh do
    logger.info 'Triggering Instance Refresh on Auto Scaling Group(s)...'
    config.autoscale_groups.each do |group|
      group.start_instance_refresh(group.launch_template)
      logger.info "Successfully started Instance Refresh on Auto Scaling Group **#{group.name}**."
    rescue Capistrano::ASG::Rolling::StartInstanceRefreshError => e
      logger.warning "Failed to start Instance Refresh on Auto Scaling Group **#{group.name}**: #{e.message}"
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
            logger.warning("AMI **#{ami.id}** does not exist for Launch Template **#{version.name}** version **#{version.version}**.")
            next
          end

          # Only clean up when AMI was tagged by us.
          next if exists && !ami.tag?('capistrano-asg-rolling:version') && !ami.tag?('capistrano-asg-rolling:gem-version')

          logger.verbose "Deleting Launch Template **#{version.name}** version **#{version.version}**..."
          version.delete

          next if deleted

          logger.verbose "Deleting AMI **#{ami.id}** and snapshots..."
          ami.delete

          deleted_amis << ami
        end
      end
    end

    instances = config.instances.auto_terminate
    if instances.any?
      logger.info 'Terminating instance(s)...'
      begin
        instances.terminate
      rescue Capistrano::ASG::Rolling::InstanceTerminateFailed => e
        logger.warning "Failed to terminate Instance **#{e.instance.id}**: #{e.message}"
      end
    end
  end

  desc 'Launch Instances by marking instances to not automatically terminate'
  task :launch_instances do
    if config.instances.any?
      config.instances.each do |instance|
        instance.auto_terminate = false
      end
    else
      raise Capistrano::ASG::Rolling::NoInstancesLaunched
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
      raise Capistrano::ASG::Rolling::NoInstancesLaunched
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

        logger.info 'Stopping instance...'
        instance.stop

        logger.info 'Creating AMI...'
        ami = instance.create_ami(description: revision_log_message, tags: Capistrano::ASG::Rolling::Tags.ami_tags)

        logger.info 'Starting instance...'
        instance.start

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
    if config.wait_for_instance_refresh?
      groups = config.autoscale_groups.to_h { |group| [group.name, group] }
      completed_groups = []

      while groups.any?
        groups.each do |name, group|
          refresh = group.latest_instance_refresh
          if refresh.nil? || refresh.completed?
            logger.info "Auto Scaling Group: **#{name}**, completed with status '#{refresh.status}'." if refresh&.completed?
            completed_groups.push groups.delete(name)
          elsif !refresh.percentage_complete.nil?
            logger.info "Auto Scaling Group: **#{name}**, #{refresh.percentage_complete}% completed, status '#{refresh.status}'."
          else
            logger.info "Auto Scaling Group: **#{name}**, status '#{refresh.status}'."
          end
        rescue Aws::AutoScaling::Errors::ServiceError => e
          # The instance refresh is still running in AWS even though we hit a
          # transient API error (typically throttling that exceeded the SDK's
          # retry budget). Log and retry on the next polling interval instead
          # of aborting the deployment.
          logger.warning "Auto Scaling Group: **#{name}**, failed to fetch status: #{e.class}: #{e.message} - retrying on next poll."
        end
        next if groups.empty?

        wait_for = config.instance_refresh_polling_interval
        logger.info "Instance refresh(es) not completed, waiting #{wait_for} seconds..."
        sleep wait_for
      end

      failed = completed_groups.any? { |group| group.latest_instance_refresh&.failed? }
      raise Capistrano::ASG::Rolling::InstanceRefreshFailed if failed
    end
  end
end
