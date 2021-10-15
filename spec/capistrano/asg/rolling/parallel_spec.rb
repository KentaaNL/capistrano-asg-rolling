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
  end
end
