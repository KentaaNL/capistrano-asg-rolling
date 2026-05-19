# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::AWS do
  let(:klass) do
    Class.new do
      include Capistrano::ASG::Rolling::AWS
    end
  end

  describe '#aws_options' do
    subject(:options) { klass.new.send(:aws_options) }

    it 'sets adaptive retry mode by default' do
      expect(options[:retry_mode]).to eq('adaptive')
    end

    it 'sets a retry limit of 10 by default' do
      expect(options[:retry_limit]).to eq(10)
    end

    context 'when overridden via Capistrano variables' do
      before do
        allow(Capistrano::ASG::Rolling::Configuration).to receive_messages(aws_retry_mode: 'standard', aws_retry_limit: 25)
      end

      it 'passes the configured retry_mode and retry_limit through' do
        expect(options[:retry_mode]).to eq('standard')
        expect(options[:retry_limit]).to eq(25)
      end
    end
  end
end
