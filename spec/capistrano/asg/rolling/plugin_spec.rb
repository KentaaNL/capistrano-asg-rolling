# frozen_string_literal: true

# Load DSL and set up stages
require 'capistrano/setup'

# Include default deployment tasks
require 'capistrano/deploy'

RSpec.describe Capistrano::ASG::Rolling::Plugin do
  include Capistrano::DSL

  it 'defines tasks when constructed #1' do
    install_plugin described_class

    expect(Rake::Task['rolling:setup']).not_to be_nil
    expect(Rake::Task['rolling:update']).not_to be_nil
    expect(Rake::Task['rolling:cleanup']).not_to be_nil
  end

  it 'defines tasks when constructed #2' do
    install_plugin described_class

    expect(Rake::Task['rolling:launch_instances']).not_to be_nil
    expect(Rake::Task['rolling:create_ami']).not_to be_nil
    expect(Rake::Task['rolling:instance_refresh_status']).not_to be_nil
  end

  describe '#config' do
    it 'exposes the config helper' do
      plugin = described_class.new
      expect(plugin.config).to eq(Capistrano::ASG::Rolling::Configuration)
    end
  end

  describe '#logger' do
    it 'exposes the logger class' do
      plugin = described_class.new
      expect(plugin.logger).to be_a(Capistrano::ASG::Rolling::Logger)
    end
  end

  describe '#add_instance' do
    let(:plugin) { described_class.new }
    let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345', '192.168.1.88', '54.194.252.215', nil, nil) }

    before { allow(plugin).to receive(:server).and_call_original }

    it 'registers the server with its IP address and merged properties' do
      plugin.add_instance(instance, roles: [:web], user: 'deployer')

      expect(plugin).to have_received(:server)
        .with('192.168.1.88', roles: [:web], user: 'deployer', instance_id: 'i-12345')
    end

    it 'always includes instance_id in the server properties' do
      plugin.add_instance(instance, {})

      expect(plugin).to have_received(:server).with(anything, hash_including(instance_id: 'i-12345'))
    end
  end

  describe '#cleanup' do
    let(:plugin) { described_class.new }
    let(:instance_auto_terminate) { Capistrano::ASG::Rolling::Instance.new('i-12345', nil, nil, nil, nil) }
    let(:instance_dont_terminate) { Capistrano::ASG::Rolling::Instance.new('i-67890', nil, nil, nil, nil) }

    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=TerminateInstances/).to_return(body: File.read('spec/support/stubs/TerminateInstances.xml'))

      allow(instance_auto_terminate).to receive(:terminate).and_call_original
      allow(instance_dont_terminate).to receive(:terminate).and_call_original

      instance_dont_terminate.auto_terminate = false
    end

    context 'when there are no instances to terminate' do
      it 'does not terminate any instances' do
        plugin.cleanup
        expect(instance_auto_terminate).not_to have_received(:terminate)
        expect(instance_dont_terminate).not_to have_received(:terminate)
      end
    end

    context 'when there are instances to terminate' do
      before do
        Capistrano::ASG::Rolling::Configuration.instances << instance_auto_terminate
        Capistrano::ASG::Rolling::Configuration.instances << instance_dont_terminate
      end

      it 'terminates the instances with auto_terminate flag' do
        plugin.cleanup
        expect(instance_auto_terminate).to have_received(:terminate)
        expect(instance_dont_terminate).not_to have_received(:terminate)
      end
    end

    context 'when InstanceTerminateFailed is raised' do
      let(:instance_failed) { Capistrano::ASG::Rolling::Instance.new('i-failed', nil, nil, nil, nil) }

      before do
        Capistrano::ASG::Rolling::Configuration.instances << instance_failed
        Capistrano::ASG::Rolling::Configuration.instances << instance_auto_terminate

        allow(instance_failed).to receive(:terminate)
          .and_raise(Capistrano::ASG::Rolling::InstanceTerminateFailed.new(instance_failed, RuntimeError.new("The instance ID 'i-12345' does not exist")))
      end

      it 'does not raise' do
        expect { plugin.cleanup }.not_to raise_error
      end

      it 'still terminates other instances' do
        plugin.cleanup
        expect(instance_auto_terminate).to have_received(:terminate)
      end

      it 'logs a warning' do
        expect { plugin.cleanup }.to output(/WARNING: Failed to terminate Instance .*i-failed.*: The instance ID 'i-12345' does not exist/).to_stdout
      end
    end
  end
end
