# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::Logger do
  subject(:logger) { described_class.new }

  describe '#info' do
    it 'outputs a message to stdout' do
      expect { logger.info('hello world') }.to output("hello world\n").to_stdout
    end

    it 'formats text as bold' do
      expect { logger.info('hello **world**') }.to output("hello \e[1mworld\e[22m\n").to_stdout
    end
  end

  describe '#warning' do
    it 'outputs a warning to stdout' do
      expect { logger.warning('hello world') }.to output("WARNING: hello world\n").to_stdout
    end

    it 'formats text as bold' do
      expect { logger.warning('hello **world**') }.to output("WARNING: hello \e[1mworld\e[22m\n").to_stdout
    end
  end

  describe '#error' do
    it 'outputs a message to stderr' do
      expect { logger.error('hello world') }.to output("\e[0;31;49mhello world\e[0m\n").to_stderr
    end

    it 'formats text as bold' do
      expect { logger.error('hello **world**') }.to output("\e[0;31;49mhello \e[1mworld\e[22m\e[0m\n").to_stderr
    end
  end

  describe '#verbose' do
    context 'when verbose is disabled' do
      it 'does nothing' do
        expect { logger.verbose('hello world') }.not_to output.to_stdout
      end
    end

    context 'when verbose is enabled' do
      subject(:logger) { described_class.new(verbose: true) }

      it 'outputs a message to stdout' do
        expect { logger.verbose('hello world') }.to output("hello world\n").to_stdout
      end

      it 'formats text as bold' do
        expect { logger.verbose('hello **world**') }.to output("hello \e[1mworld\e[22m\n").to_stdout
      end
    end
  end
end
