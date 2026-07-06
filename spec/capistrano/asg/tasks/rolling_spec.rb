# frozen_string_literal: true

require 'capistrano/setup'
require 'capistrano/deploy'

RSpec.describe 'rolling rake tasks' do # rubocop:disable RSpec/DescribeClass
  include Capistrano::DSL

  # Clear any accumulated task actions from prior examples or other spec files
  # (plugin_spec.rb installs the plugin with hooks per example), reenable all
  # tasks, then install a single fresh plugin instance. `install_plugin` returns
  # the load:defaults Rake::Task, not the plugin, so we instantiate explicitly.
  let(:plugin) do
    Rake.application.tasks.each do |t|
      t.actions.clear
      t.reenable
    end
    Capistrano::ASG::Rolling::Plugin.new.tap do |p|
      install_plugin(p, load_hooks: false, load_immediately: true)
    end
  end

  let(:logger) do
    instance_double(Capistrano::ASG::Rolling::Logger).tap do |l|
      allow(l).to receive(:info)
      allow(l).to receive(:verbose)
      allow(l).to receive(:warning)
      allow(l).to receive(:error)
    end
  end

  let(:group) { Capistrano::ASG::Rolling::AutoscaleGroup.new('asg-web', roles: [:web], user: 'deployer') }
  let(:launch_template) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 1, 'MyLaunchTemplate') }

  before do
    allow(plugin).to receive(:logger).and_return(logger)
    allow(plugin).to receive(:on)
    allow(plugin).to receive(:server)
    allow(plugin).to receive(:invoke)
  end

  def run_task(name)
    Rake::Task[name].execute
  end

  describe 'rolling:setup' do
    it 'invokes rolling:prepare' do
      expect(Rake::Task['rolling:setup'].prerequisites).to include('rolling:prepare')
    end

    it 'invokes rolling:wait_for_ssh' do
      expect(Rake::Task['rolling:setup'].prerequisites).to include('rolling:wait_for_ssh')
    end
  end

  describe 'rolling:prepare' do
    let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345', '10.0.0.1', nil, 'ami-existing', group) }

    before do
      allow(launch_template).to receive(:image_id).and_return('ami-existing')
      allow(Capistrano::ASG::Rolling::Configuration).to receive(:instance_overrides).and_return(nil)
    end

    context 'when group uses rolling strategy and no instance with that image is tracked' do
      before do
        allow(group).to receive(:launch_template).and_return(launch_template)
        allow(Capistrano::ASG::Rolling::Configuration).to receive(:autoscale_groups)
          .and_return(Capistrano::ASG::Rolling::AutoscaleGroups.new([group]))
        allow(Capistrano::ASG::Rolling::Instance).to receive(:run).and_return(instance)
      end

      it 'launches a new instance' do
        run_task('rolling:prepare')
        expect(Capistrano::ASG::Rolling::Instance).to have_received(:run)
          .with(autoscaling_group: group, overrides: nil)
      end

      it 'adds the new instance to the server list' do
        run_task('rolling:prepare')
        expect(plugin).to have_received(:server).with('10.0.0.1', hash_including(roles: [:web]))
      end
    end

    context 'when instance_overrides is configured' do
      let(:overrides) { { instance_type: 'c5.large' } }

      before do
        allow(Capistrano::ASG::Rolling::Configuration).to receive_messages(
          instance_overrides: overrides,
          autoscale_groups: Capistrano::ASG::Rolling::AutoscaleGroups.new([group])
        )
        allow(group).to receive(:launch_template).and_return(launch_template)
        allow(Capistrano::ASG::Rolling::Instance).to receive(:run).and_return(instance)
      end

      it 'passes instance_overrides to the run call' do
        run_task('rolling:prepare')
        expect(Capistrano::ASG::Rolling::Instance).to have_received(:run)
          .with(autoscaling_group: group, overrides: overrides)
      end
    end

    context 'when multiple rolling groups each need an instance' do
      let(:group2) { Capistrano::ASG::Rolling::AutoscaleGroup.new('asg-worker', roles: [:worker], user: 'deployer') }
      let(:launch_template2) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-0987654321', 1, 'WorkerTemplate') }
      let(:instance2) { Capistrano::ASG::Rolling::Instance.new('i-67890', '10.0.0.2', nil, 'ami-other', group2) }

      before do
        allow(group).to receive(:launch_template).and_return(launch_template)
        allow(group2).to receive(:launch_template).and_return(launch_template2)
        allow(launch_template2).to receive(:image_id).and_return('ami-other')
        allow(Capistrano::ASG::Rolling::Configuration).to receive(:autoscale_groups)
          .and_return(Capistrano::ASG::Rolling::AutoscaleGroups.new([group, group2]))
        allow(Capistrano::ASG::Rolling::Instance).to receive(:run)
          .with(autoscaling_group: group, overrides: nil).and_return(instance)
        allow(Capistrano::ASG::Rolling::Instance).to receive(:run)
          .with(autoscaling_group: group2, overrides: nil).and_return(instance2)
      end

      it 'launches an instance for each group' do
        run_task('rolling:prepare')
        expect(Capistrano::ASG::Rolling::Instance).to have_received(:run).twice
      end

      it 'adds both instances to the server list' do
        run_task('rolling:prepare')
        expect(plugin).to have_received(:server).with('10.0.0.1', hash_including(roles: [:web]))
        expect(plugin).to have_received(:server).with('10.0.0.2', hash_including(roles: [:worker]))
      end
    end

    context 'when two rolling groups share the same launch template image' do
      let(:group2) { Capistrano::ASG::Rolling::AutoscaleGroup.new('asg-worker', roles: [:worker], user: 'deployer') }

      before do
        allow(group).to receive(:launch_template).and_return(launch_template)
        allow(group2).to receive(:launch_template).and_return(launch_template)
        allow(Capistrano::ASG::Rolling::Configuration).to receive(:autoscale_groups)
          .and_return(Capistrano::ASG::Rolling::AutoscaleGroups.new([group, group2]))
        allow(Capistrano::ASG::Rolling::Instance).to receive(:run).and_return(instance)
      end

      it 'only launches one instance' do
        run_task('rolling:prepare')
        expect(Capistrano::ASG::Rolling::Instance).to have_received(:run).once
      end
    end

    context 'when group uses standard (non-rolling) strategy' do
      let(:group) { Capistrano::ASG::Rolling::AutoscaleGroup.new('asg-web', rolling: false, roles: [:web], user: 'deployer') }

      before do
        allow(group).to receive(:instances).and_return([instance])
        allow(Capistrano::ASG::Rolling::Configuration).to receive(:autoscale_groups)
          .and_return(Capistrano::ASG::Rolling::AutoscaleGroups.new([group]))
      end

      it 'adds existing instances to the server list' do
        run_task('rolling:prepare')
        expect(plugin).to have_received(:server).with('10.0.0.1', hash_including(roles: [:web]))
      end
    end

    context 'when group uses standard strategy with primary_roles' do
      let(:instance2) { Capistrano::ASG::Rolling::Instance.new('i-67890', '10.0.0.3', nil, 'ami-existing', nil) }
      let(:group) { Capistrano::ASG::Rolling::AutoscaleGroup.new('asg-web', rolling: false, roles: [:web], primary_roles: %i[web db], user: 'deployer') }

      before do
        allow(group).to receive(:instances).and_return([instance, instance2])
        allow(Capistrano::ASG::Rolling::Configuration).to receive(:autoscale_groups)
          .and_return(Capistrano::ASG::Rolling::AutoscaleGroups.new([group]))
      end

      it 'uses primary_roles as the roles for the first instance' do
        run_task('rolling:prepare')
        expect(plugin).to have_received(:server)
          .with('10.0.0.1', hash_including(roles: %i[web db]))
      end

      it 'does not pass the primary_roles key in the first server call' do
        run_task('rolling:prepare')
        expect(plugin).not_to have_received(:server)
          .with('10.0.0.1', hash_including(primary_roles: anything))
      end

      it 'uses standard roles for subsequent instances' do
        run_task('rolling:prepare')
        expect(plugin).to have_received(:server)
          .with('10.0.0.3', hash_including(roles: [:web]))
      end
    end

    context 'when no groups are configured' do
      before do
        allow(Capistrano::ASG::Rolling::Configuration).to receive(:autoscale_groups)
          .and_return(Capistrano::ASG::Rolling::AutoscaleGroups.new)
      end

      it 'does not wait for SSH availability' do
        run_task('rolling:prepare')
        expect(plugin).not_to have_received(:on)
      end
    end
  end

  describe 'rolling:wait_for_ssh' do
    before do
      allow(Capistrano::ASG::Rolling::SSH).to receive(:wait_for_availability)
    end

    context 'when instances have been launched' do
      before do
        Capistrano::ASG::Rolling::Configuration.instances << Capistrano::ASG::Rolling::Instance.new('i-12345', '10.0.0.1', nil, nil, nil)
        allow(plugin).to receive(:on).and_yield
      end

      it 'waits for SSH availability' do
        run_task('rolling:wait_for_ssh')
        expect(Capistrano::ASG::Rolling::SSH).to have_received(:wait_for_availability)
      end
    end

    context 'when no instances have been launched' do
      it 'does not wait for SSH availability' do
        run_task('rolling:wait_for_ssh')
        expect(plugin).not_to have_received(:on)
      end
    end
  end

  describe 'rolling:update' do
    let(:instances) { instance_double(Capistrano::ASG::Rolling::Instances) }
    let(:ami) { Capistrano::ASG::Rolling::AMI.new('ami-new') }
    let(:autoscale_groups) { instance_double(Capistrano::ASG::Rolling::AutoscaleGroups) }
    let(:asgs_launch_templates) { instance_double(Capistrano::ASG::Rolling::LaunchTemplates) }
    let(:updated_templates) { instance_double(Capistrano::ASG::Rolling::LaunchTemplates) }
    let(:config_launch_templates) { instance_double(Capistrano::ASG::Rolling::LaunchTemplates) }
    let(:groups_with_lt) { instance_double(Capistrano::ASG::Rolling::AutoscaleGroups) }

    before do
      allow(Capistrano::ASG::Rolling::Tags).to receive(:ami_tags).and_return({})
      allow(plugin).to receive(:revision_log_message).and_return('deploy by deployer')
    end

    context 'when rolling_update? is false' do
      before do
        allow(Capistrano::ASG::Rolling::Configuration).to receive_messages(rolling_update?: false, instances: instances)
        allow(instances).to receive(:stop)
      end

      it 'does not stop instances' do
        run_task('rolling:update')
        expect(instances).not_to have_received(:stop)
      end
    end

    context 'when instances are empty' do
      before do
        allow(Capistrano::ASG::Rolling::Configuration).to receive_messages(rolling_update?: true, instances: instances)
        allow(instances).to receive(:empty?).and_return(true)
        allow(instances).to receive(:stop)
      end

      it 'does not stop instances' do
        run_task('rolling:update')
        expect(instances).not_to have_received(:stop)
      end
    end

    context 'when rolling_update? is true and instances exist' do
      before do
        allow(Capistrano::ASG::Rolling::Configuration).to receive_messages(rolling_update?: true, instances: instances, autoscale_groups: autoscale_groups, launch_templates: config_launch_templates)

        allow(instances).to receive(:stop)
        allow(instances).to receive_messages(empty?: false, create_ami: [ami])

        allow(autoscale_groups).to receive(:launch_templates).and_return(asgs_launch_templates)
        allow(autoscale_groups).to receive(:with_launch_template).with(launch_template).and_return(groups_with_lt)

        allow(asgs_launch_templates).to receive(:update).and_return(updated_templates)
        allow(updated_templates).to receive(:flat_map) { |&block| [launch_template].flat_map(&block) }

        allow(groups_with_lt).to receive(:map) { |&block| [group].map(&block) }
        allow(group).to receive(:start_instance_refresh)

        allow(config_launch_templates).to receive(:merge)
      end

      it 'stops instances' do
        run_task('rolling:update')
        expect(instances).to have_received(:stop)
      end

      it 'creates AMIs from instances' do
        run_task('rolling:update')
        expect(instances).to have_received(:create_ami)
          .with(description: 'deploy by deployer', tags: {})
      end

      it 'updates launch templates with new AMIs' do
        run_task('rolling:update')
        expect(asgs_launch_templates).to have_received(:update)
          .with(amis: [ami], description: 'deploy by deployer')
      end

      it 'triggers instance refresh on each group' do
        run_task('rolling:update')
        expect(group).to have_received(:start_instance_refresh).with(launch_template)
      end

      it 'merges updated templates into config' do
        run_task('rolling:update')
        expect(config_launch_templates).to have_received(:merge).with(updated_templates)
      end
    end

    context 'when StartInstanceRefreshError is raised' do
      before do
        allow(Capistrano::ASG::Rolling::Configuration).to receive_messages(rolling_update?: true, instances: instances, autoscale_groups: autoscale_groups, launch_templates: config_launch_templates)

        allow(instances).to receive(:stop)
        allow(instances).to receive_messages(empty?: false, create_ami: [ami])

        allow(autoscale_groups).to receive_messages(launch_templates: asgs_launch_templates, with_launch_template: groups_with_lt)
        allow(asgs_launch_templates).to receive(:update).and_return(updated_templates)
        allow(updated_templates).to receive(:flat_map) { |&block| [launch_template].flat_map(&block) }

        allow(groups_with_lt).to receive(:map) { |&block| [group].map(&block) }
        allow(group).to receive(:start_instance_refresh)
          .and_raise(Capistrano::ASG::Rolling::StartInstanceRefreshError, 'already in progress')

        allow(config_launch_templates).to receive(:merge)
      end

      it 'does not raise' do
        expect { run_task('rolling:update') }.not_to raise_error
      end
    end
  end

  describe 'rolling:trigger_instance_refresh' do
    before do
      allow(group).to receive(:launch_template).and_return(launch_template)
      allow(Capistrano::ASG::Rolling::Configuration).to receive(:autoscale_groups).and_return([group])
    end

    context 'when instance refresh starts successfully' do
      before do
        allow(group).to receive(:start_instance_refresh)
      end

      it 'starts instance refresh on each group' do
        run_task('rolling:trigger_instance_refresh')
        expect(group).to have_received(:start_instance_refresh).with(launch_template)
      end
    end

    context 'when StartInstanceRefreshError is raised' do
      before do
        allow(group).to receive(:start_instance_refresh)
          .and_raise(Capistrano::ASG::Rolling::StartInstanceRefreshError, 'already in progress')
      end

      it 'does not raise' do
        expect { run_task('rolling:trigger_instance_refresh') }.not_to raise_error
      end

      it 'logs the failure' do
        run_task('rolling:trigger_instance_refresh')
        expect(logger).to have_received(:warning).with(/Failed to start Instance Refresh/)
      end
    end

    context 'when multiple groups have partial failure' do
      let(:group2) { Capistrano::ASG::Rolling::AutoscaleGroup.new('asg-db') }

      before do
        allow(group2).to receive(:launch_template).and_return(launch_template)
        allow(group).to receive(:start_instance_refresh)
          .and_raise(Capistrano::ASG::Rolling::StartInstanceRefreshError, 'already in progress')
        allow(group2).to receive(:start_instance_refresh)
        allow(Capistrano::ASG::Rolling::Configuration).to receive(:autoscale_groups)
          .and_return([group, group2])
      end

      it 'continues to the next group after an error' do
        run_task('rolling:trigger_instance_refresh')
        expect(group2).to have_received(:start_instance_refresh)
      end
    end
  end

  describe 'rolling:cleanup' do
    let(:ami) { Capistrano::ASG::Rolling::AMI.new('ami-old') }
    let(:version) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 2, 'MyLaunchTemplate') }
    let(:launch_template) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 3, 'MyLaunchTemplate') }
    let(:launch_templates) { instance_double(Capistrano::ASG::Rolling::LaunchTemplates) }
    let(:instances) { instance_double(Capistrano::ASG::Rolling::Instances) }
    let(:auto_terminate_instances) { instance_double(Capistrano::ASG::Rolling::Instances) }

    before do
      allow(Capistrano::ASG::Rolling::Configuration).to receive_messages(launch_templates: launch_templates, instances: instances, keep_versions: 0)
      allow(instances).to receive(:auto_terminatable).and_return(auto_terminate_instances)
      allow(auto_terminate_instances).to receive(:any?).and_return(false)
      allow(launch_templates).to receive(:empty?).and_return(false)
      allow(launch_templates).to receive(:each).and_yield(launch_template)
      allow(launch_template).to receive(:previous_versions).and_return([version])
      allow(version).to receive(:ami).and_return(ami)
    end

    context 'when launch templates are empty' do
      before do
        allow(launch_templates).to receive(:empty?).and_return(true)
        allow(version).to receive(:delete)
      end

      it 'does not attempt to delete any versions' do
        run_task('rolling:cleanup')
        expect(version).not_to have_received(:delete)
      end
    end

    context 'when a version has an existing, tagged AMI' do
      before do
        allow(ami).to receive(:exists?).and_return(true)
        allow(ami).to receive(:tag?).with('capistrano-asg-rolling:version').and_return(true)
        allow(ami).to receive(:delete)
        allow(version).to receive(:delete)
      end

      it 'deletes the launch template version' do
        run_task('rolling:cleanup')
        expect(version).to have_received(:delete)
      end

      it 'deletes the AMI' do
        run_task('rolling:cleanup')
        expect(ami).to have_received(:delete)
      end
    end

    context 'when the AMI does not exist' do
      before do
        allow(ami).to receive(:exists?).and_return(false)
        allow(version).to receive(:delete)
      end

      it 'logs a warning' do
        run_task('rolling:cleanup')
        expect(logger).to have_received(:warning).with(/does not exist/)
      end

      it 'does not delete the launch template version' do
        run_task('rolling:cleanup')
        expect(version).not_to have_received(:delete)
      end
    end

    context 'when the same AMI appears in two versions (duplicate)' do
      let(:version2) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 2, 'MyLaunchTemplate') }

      before do
        allow(launch_template).to receive(:previous_versions).and_return([version, version2])
        allow(version2).to receive(:ami).and_return(ami)
        allow(ami).to receive(:exists?).and_return(true)
        allow(ami).to receive(:tag?).with('capistrano-asg-rolling:version').and_return(true)
        allow(ami).to receive(:delete)
        allow(version).to receive(:delete)
        allow(version2).to receive(:delete)
      end

      it 'deletes the AMI only once' do
        run_task('rolling:cleanup')
        expect(ami).to have_received(:delete).once
      end

      it 'deletes both launch template versions' do
        run_task('rolling:cleanup')
        expect(version).to have_received(:delete)
        expect(version2).to have_received(:delete)
      end
    end

    context "when a version's AMI was already deleted in the same run" do
      let(:version2) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 2, 'MyLaunchTemplate') }

      before do
        allow(launch_template).to receive(:previous_versions).and_return([version, version2])
        allow(version2).to receive(:ami).and_return(ami)
        # First iteration: AMI exists → deleted. Second iteration: AMI no longer exists.
        allow(ami).to receive(:exists?).and_return(true, false)
        allow(ami).to receive(:tag?).with('capistrano-asg-rolling:version').and_return(true)
        allow(ami).to receive(:delete)
        allow(version).to receive(:delete)
        allow(version2).to receive(:delete)
      end

      it 'does not log a warning for the already-deleted AMI' do
        run_task('rolling:cleanup')
        expect(logger).not_to have_received(:warning)
      end

      it 'still deletes the second launch template version' do
        run_task('rolling:cleanup')
        expect(version2).to have_received(:delete)
      end

      it 'does not attempt to delete the AMI a second time' do
        run_task('rolling:cleanup')
        expect(ami).to have_received(:delete).once
      end
    end

    context 'when the AMI exists but is not tagged by this gem' do
      before do
        allow(ami).to receive(:exists?).and_return(true)
        allow(ami).to receive(:tag?).with('capistrano-asg-rolling:version').and_return(false)
        allow(ami).to receive(:tag?).with('capistrano-asg-rolling:gem-version').and_return(false)
        allow(version).to receive(:delete)
        allow(ami).to receive(:delete)
      end

      it 'does not delete the launch template version' do
        run_task('rolling:cleanup')
        expect(version).not_to have_received(:delete)
      end

      it 'does not delete the AMI' do
        run_task('rolling:cleanup')
        expect(ami).not_to have_received(:delete)
      end
    end

    context 'when keep_versions is 1' do
      let(:version2) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 2, 'MyLaunchTemplate') }

      before do
        allow(Capistrano::ASG::Rolling::Configuration).to receive(:keep_versions).and_return(1)
        allow(launch_template).to receive(:previous_versions).and_return([version, version2])
        allow(version2).to receive(:ami).and_return(ami)
        allow(version).to receive(:delete)
        allow(version2).to receive(:delete)
        allow(ami).to receive_messages(exists?: true, delete: nil)
        allow(ami).to receive(:tag?).with('capistrano-asg-rolling:version').and_return(true)
      end

      it 'keeps the most recent version and deletes only older ones' do
        run_task('rolling:cleanup')
        expect(version).not_to have_received(:delete)
        expect(version2).to have_received(:delete)
      end
    end

    context 'when auto-terminate instances exist' do
      before do
        allow(launch_templates).to receive(:empty?).and_return(true)
        allow(auto_terminate_instances).to receive(:any?).and_return(true)
        allow(auto_terminate_instances).to receive(:terminate)
      end

      it 'terminates the instances' do
        run_task('rolling:cleanup')
        expect(auto_terminate_instances).to have_received(:terminate)
      end
    end

    context 'when InstanceTerminateFailed is raised' do
      let(:failed_instance) { Capistrano::ASG::Rolling::Instance.new('i-failed', nil, nil, nil, nil) }

      before do
        allow(launch_templates).to receive(:empty?).and_return(true)
        allow(auto_terminate_instances).to receive(:any?).and_return(true)
        allow(auto_terminate_instances).to receive(:terminate)
          .and_raise(Capistrano::ASG::Rolling::InstanceTerminateFailed.new(
                       failed_instance, RuntimeError.new('timeout')
                     ))
      end

      it 'does not raise' do
        expect { run_task('rolling:cleanup') }.not_to raise_error
      end

      it 'logs a warning' do
        run_task('rolling:cleanup')
        expect(logger).to have_received(:warning).with(/Failed to terminate/)
      end
    end
  end

  describe 'rolling:launch_instances' do
    let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345', nil, nil, nil, nil) }

    before do
      allow(Capistrano::ASG::Rolling::Configuration).to receive(:instances)
        .and_return(Capistrano::ASG::Rolling::Instances.new([instance]))
    end

    context 'when instances are present' do
      before do
        allow(instance).to receive(:auto_terminate=)
      end

      it 'marks each instance to not auto-terminate' do
        run_task('rolling:launch_instances')
        expect(instance).to have_received(:auto_terminate=).with(false)
      end
    end

    context 'when no instances have been launched' do
      before do
        allow(Capistrano::ASG::Rolling::Configuration).to receive(:instances)
          .and_return(Capistrano::ASG::Rolling::Instances.new([]))
      end

      it 'raises NoInstancesLaunched' do
        expect { run_task('rolling:launch_instances') }
          .to raise_error(Capistrano::ASG::Rolling::NoInstancesLaunched)
      end
    end
  end

  describe 'rolling:deploy_test' do
    let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345', nil, nil, nil, nil) }

    before do
      allow(Capistrano::ASG::Rolling::Configuration).to receive(:instances)
        .and_return(Capistrano::ASG::Rolling::Instances.new([instance]))
    end

    context 'when instances are present' do
      before do
        allow(instance).to receive(:auto_terminate=)
        allow(Capistrano::ASG::Rolling::Configuration).to receive(:rolling_update=)
      end

      it 'sets rolling_update to false' do
        run_task('rolling:deploy_test')
        expect(Capistrano::ASG::Rolling::Configuration).to have_received(:rolling_update=).with(false)
      end

      it 'marks each instance to not auto-terminate' do
        run_task('rolling:deploy_test')
        expect(instance).to have_received(:auto_terminate=).with(false)
      end

      it 'invokes the deploy task' do
        run_task('rolling:deploy_test')
        expect(plugin).to have_received(:invoke).with('deploy')
      end
    end

    context 'when no instances have been launched' do
      before do
        allow(Capistrano::ASG::Rolling::Configuration).to receive(:instances)
          .and_return(Capistrano::ASG::Rolling::Instances.new([]))
      end

      it 'raises NoInstancesLaunched' do
        expect { run_task('rolling:deploy_test') }
          .to raise_error(Capistrano::ASG::Rolling::NoInstancesLaunched)
      end

      it 'does not invoke the deploy task' do
        expect { run_task('rolling:deploy_test') }
          .to raise_error(Capistrano::ASG::Rolling::NoInstancesLaunched)
        expect(plugin).not_to have_received(:invoke)
      end
    end
  end

  describe 'rolling:create_ami' do
    let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345', nil, nil, nil, nil) }
    let(:ami) { Capistrano::ASG::Rolling::AMI.new('ami-new') }
    let(:new_template) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-1234567890', 2, 'MyLaunchTemplate') }
    let(:launch_templates) { instance_double(Capistrano::ASG::Rolling::LaunchTemplates) }

    before do
      allow(Capistrano::ASG::Rolling::Configuration).to receive_messages(autoscale_groups: [group], launch_templates: launch_templates)
      allow(Capistrano::ASG::Rolling::Tags).to receive(:ami_tags).and_return({})
      allow(plugin).to receive(:revision_log_message).and_return('deploy by deployer')
    end

    context 'when an instance is available' do
      before do
        allow(group).to receive(:enter_standby)
        allow(group).to receive(:exit_standby)
        allow(group).to receive_messages(instances: [instance], launch_template: launch_template)
        allow(instance).to receive(:stop)
        allow(instance).to receive(:start)
        allow(instance).to receive(:create_ami).and_return(ami)
        allow(launch_template).to receive(:create_version).and_return(new_template)
        allow(launch_templates).to receive(:<<)
      end

      it 'enters standby before creating the AMI' do
        run_task('rolling:create_ami')
        expect(group).to have_received(:enter_standby).with(instance)
      end

      it 'stops the instance' do
        run_task('rolling:create_ami')
        expect(instance).to have_received(:stop)
      end

      it 'creates an AMI from the instance' do
        run_task('rolling:create_ami')
        expect(instance).to have_received(:create_ami)
          .with(description: 'deploy by deployer', tags: {})
      end

      it 'starts the instance after AMI creation' do
        run_task('rolling:create_ami')
        expect(instance).to have_received(:start)
      end

      it 'exits standby after AMI creation' do
        run_task('rolling:create_ami')
        expect(group).to have_received(:exit_standby).with(instance)
      end

      it 'creates a new launch template version with the new AMI' do
        run_task('rolling:create_ami')
        expect(launch_template).to have_received(:create_version)
          .with(image_id: 'ami-new', description: 'deploy by deployer')
      end

      it 'adds the new template version to tracked templates, not the old one' do
        run_task('rolling:create_ami')
        expect(launch_templates).to have_received(:<<).with(equal(new_template))
        expect(launch_templates).not_to have_received(:<<).with(equal(launch_template))
      end
    end

    context 'when no instance is available in the group' do
      before do
        allow(group).to receive(:instances).and_return([])
        allow(group).to receive(:enter_standby)
      end

      it 'logs an error' do
        run_task('rolling:create_ami')
        expect(logger).to have_received(:error).with(/Unable to create AMI/)
      end

      it 'does not enter standby' do
        run_task('rolling:create_ami')
        expect(group).not_to have_received(:enter_standby)
      end
    end
  end

  describe 'rolling:instance_refresh_status' do
    let(:completed_status) do
      Capistrano::ASG::Rolling::AutoscaleGroup::InstanceRefreshStatus.new('Successful', 100)
    end
    let(:failed_status) do
      Capistrano::ASG::Rolling::AutoscaleGroup::InstanceRefreshStatus.new('Failed', nil)
    end
    let(:in_progress_status) do
      Capistrano::ASG::Rolling::AutoscaleGroup::InstanceRefreshStatus.new('InProgress', 50)
    end

    before do
      allow(plugin).to receive(:sleep)
      allow(group).to receive(:refresh_id).and_return('refresh-123')
      allow(Capistrano::ASG::Rolling::Configuration).to receive_messages(
        instance_refresh_polling_interval: 1,
        wait_for_instance_refresh?: true,
        autoscale_groups: [group]
      )
    end

    context 'when wait_for_instance_refresh? is false' do
      before do
        allow(Capistrano::ASG::Rolling::Configuration).to receive(:wait_for_instance_refresh?).and_return(false)
      end

      it 'completes without checking any groups' do
        run_task('rolling:instance_refresh_status')
        expect(Capistrano::ASG::Rolling::Configuration).not_to have_received(:autoscale_groups)
      end
    end

    context 'when refresh is already completed' do
      before do
        allow(group).to receive(:latest_instance_refresh).and_return(completed_status)
      end

      it 'completes without error' do
        expect { run_task('rolling:instance_refresh_status') }.not_to raise_error
      end

      it 'does not sleep' do
        run_task('rolling:instance_refresh_status')
        expect(plugin).not_to have_received(:sleep)
      end
    end

    context 'when refresh returns nil (no previous refresh)' do
      before do
        allow(group).to receive(:latest_instance_refresh).and_return(nil)
      end

      it 'completes without error' do
        expect { run_task('rolling:instance_refresh_status') }.not_to raise_error
      end
    end

    context 'when refresh takes two polls to complete' do
      before do
        allow(group).to receive(:latest_instance_refresh)
          .and_return(in_progress_status, completed_status)
      end

      it 'completes without error' do
        expect { run_task('rolling:instance_refresh_status') }.not_to raise_error
      end

      it 'sleeps once between polls' do
        run_task('rolling:instance_refresh_status')
        expect(plugin).to have_received(:sleep).once
      end
    end

    context 'when refresh completes with a failed status' do
      before do
        allow(group).to receive(:latest_instance_refresh).and_return(failed_status)
      end

      it 'raises InstanceRefreshFailed' do
        expect { run_task('rolling:instance_refresh_status') }
          .to raise_error(Capistrano::ASG::Rolling::InstanceRefreshFailed)
      end
    end

    context 'when a ServiceError is raised during polling' do
      let(:service_error) { Aws::AutoScaling::Errors::ServiceError.new(nil, 'Throttled') }

      before do
        call_count = 0
        allow(group).to receive(:latest_instance_refresh) do
          call_count += 1
          raise service_error if call_count == 1

          completed_status
        end
      end

      it 'does not raise' do
        expect { run_task('rolling:instance_refresh_status') }.not_to raise_error
      end

      it 'logs a warning about the error' do
        run_task('rolling:instance_refresh_status')
        expect(logger).to have_received(:warning).with(/failed to fetch status/)
      end
    end
  end
end
