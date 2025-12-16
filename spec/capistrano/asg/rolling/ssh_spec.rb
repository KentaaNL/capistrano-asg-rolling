# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::SSH do
  let(:backend) { instance_double(SSHKit::Backend::Netssh) }

  describe '.wait_for_availability' do
    before do
      allow(described_class).to receive(:available?).and_return(false, true)
    end

    it 'waits until SSH is available' do
      described_class.wait_for_availability(backend)

      expect(described_class).to have_received(:available?).with(backend).twice
    end

    context 'when timing out' do
      before do
        allow(described_class).to receive(:available?).and_return(false)

        stub_const('Capistrano::ASG::Rolling::SSH::WAIT_TIMEOUT', 1)
      end

      it 'raises an SSHAvailabilityTimeoutError' do
        expect { described_class.wait_for_availability(backend) }.to raise_error(Capistrano::ASG::Rolling::SSHAvailabilityTimeoutError)
      end
    end
  end

  describe '.available?' do
    context 'when no exception is raised' do
      it 'is available' do
        allow(backend).to receive(:test)

        expect(described_class.available?(backend)).to be true
      end
    end

    context 'when an AuthenticationFailed is raised' do
      it 'is available' do
        allow(backend).to receive(:test).and_raise(Net::SSH::AuthenticationFailed)

        expect(described_class.available?(backend)).to be true
      end
    end

    context 'when an ConnectionTimeout is raised' do
      it 'is not available' do
        allow(backend).to receive(:test).and_raise(Net::SSH::ConnectionTimeout)

        expect(described_class.available?(backend)).to be false
      end
    end

    context 'when an Proxy::ConnectError is raised' do
      it 'is not available' do
        allow(backend).to receive(:test).and_raise(Net::SSH::Proxy::ConnectError)

        expect(described_class.available?(backend)).to be false
      end
    end
  end
end
