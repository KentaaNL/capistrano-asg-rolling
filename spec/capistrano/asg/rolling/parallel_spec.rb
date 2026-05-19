# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::Parallel do
  describe '.run' do
    it 'runs code parallel' do
      result = described_class.run([1, 2, 3, 4]) { |n| n * 2 }
      expect(result.sort).to eq([2, 4, 6, 8])
    end

    it 'returns the result as a Concurrent::Array' do
      result = described_class.run([1, 2, 3, 4]) { |n| n * 2 }
      expect(result).to be_a(Concurrent::Array)
    end

    context 'when a block raises' do
      let(:completed) { Concurrent::Array.new }
      let(:work) do
        lambda do |w|
          raise 'boom' if w == :fail

          sleep 0.05
          completed << w
        end
      end

      it 'waits for the other blocks to finish before re-raising' do
        expect { described_class.run(%i[fail ok ok], &work) }.to raise_error(RuntimeError, 'boom')
        expect(completed.size).to eq(2)
      end

      it 'warns for additional errors beyond the first' do
        allow(Kernel).to receive(:warn)

        expect do
          described_class.run([1, 2]) { |n| raise "boom #{n}" }
        end.to raise_error(RuntimeError, /boom/)

        expect(Kernel).to have_received(:warn).with(/parallel task failed.*boom/).once
      end
    end
  end
end
