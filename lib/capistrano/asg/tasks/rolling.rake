# frozen_string_literal: true

namespace :rolling do
  desc 'Setup servers to be used for (rolling) deployment'
  task :setup do
    rolling_groups_to_launch = []
    standard_groups = []

    config.autoscale_groups.each do |group|
      if group.rolling?
        logger.info "Auto Scaling Group: **#{group.name}**, rolling deployment strategy."

        # If we've already launched an instance with this image, then skip it.
        # Note: dedupe across this run is preserved below when we add launches.
        rolling_groups_to_launch << group
      else
        logger.info "Auto Scaling Group: **#{group.name}**, standard deployment strategy."
        standard_groups << group
      end
    end

    # Launch one instance per rolling ASG in parallel. The serial version waited
    # on EC2 `wait_until_running` (30-90s) once per group; this collapses the
    # total wait to roughly the slowest single launch.
    unless rolling_groups_to_launch.empty?
      launched_image_ids = config.instances.map(&:image_id)
      groups_needing_launch = rolling_groups_to_launch.reject do |group|
        image_id = group.launch_template.image_id
        if launched_image_ids.include?(image_id)
          true
        else
          launched_image_ids << image_id
          false
        end
      end

      # Register each launched instance immediately so the at_exit cleanup
      # hook can terminate it if a sibling launch fails and aborts the deploy.
      # `Instances#<<` wraps a plain Array; serialise with a mutex.
      register_mutex = Mutex.new

      results = Capistrano::ASG::Rolling::Parallel.run(groups_needing_launch) do |group|
        instance = Capistrano::ASG::Rolling::Instance.run(autoscaling_group: group, overrides: config.instance_overrides)
        register_mutex.synchronize { config.instances << instance }
        [group, instance]
      end

      results.each do |group, instance|
        logger.info "Launched Instance: **#{instance.id}**"
        add_instance(instance, group.properties)
      end
    end

    standard_groups.each do |group|
      group.instances.each_with_index do |instance, index|
        if index.zero? && group.properties.key?(:primary_roles)
          server_properties = group.properties.dup
          server_properties[:roles] = server_properties.delete(:primary_roles)
        else
          server_properties = group.properties
        end

        add_instance(instance, server_properties)
      end
    end

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
      refresh_pairs = updated_templates.flat_map do |launch_template|
        config.autoscale_groups.with_launch_template(launch_template).map { |group| [group, launch_template] }
      end

      Capistrano::ASG::Rolling::Parallel.run(refresh_pairs) do |group, launch_template|
        group.start_instance_refresh(launch_template)
        logger.verbose "Successfully started Instance Refresh on Auto Scaling Group **#{group.name}**."
      rescue Capistrano::ASG::Rolling::StartInstanceRefreshError => e
        logger.info "Failed to start Instance Refresh on Auto Scaling Group **#{group.name}**: #{e.message}"
      end

      config.launch_templates.merge(updated_templates)
    end
  end

  desc 'Trigger instance refresh of deployed autoscaling groups'
  task :trigger_instance_refresh do
    logger.info 'Triggering Instance Refresh on Auto Scaling Group(s)...'
    Capistrano::ASG::Rolling::Parallel.run(config.autoscale_groups.to_a) do |group|
      group.start_instance_refresh(group.launch_template)
      logger.info "Successfully started Instance Refresh on Auto Scaling Group **#{group.name}**."
    rescue Capistrano::ASG::Rolling::StartInstanceRefreshError => e
      logger.info "Failed to start Instance Refresh on Auto Scaling Group **#{group.name}**: #{e.message}"
    end
  end

  desc 'Clean up old Launch Template versions and AMIs and terminate instances'
  task :cleanup do
    unless config.launch_templates.empty?
      # Shared across threads so launch templates sharing an AMI don't both try
      # to delete the same AMI/snapshots.
      deleted_amis = Concurrent::Array.new

      logger.info 'Cleaning up old Launch Template version(s) and AMI(s)...'
      Capistrano::ASG::Rolling::Parallel.run(config.launch_templates.to_a) do |launch_template|
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
            logger.info "Auto Scaling Group: **#{name}**, completed with status '#{refresh.status}'." if refresh.completed?
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

      failed = completed_groups.any? { |group| group.latest_instance_refresh.failed? }
      raise Capistrano::ASG::Rolling::InstanceRefreshFailed if failed
    end
  end
end
