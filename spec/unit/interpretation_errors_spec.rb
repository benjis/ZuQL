# frozen_string_literal: true

RSpec.describe ZuQL::InterpretationError do
  it 'deep-copies and freezes structured details' do
    reason = +'invalid shape'
    details = { reasons: [reason] }

    error = described_class.new(details: details)
    reason << ' changed'
    details[:reasons] << 'another reason'

    expect(error.details).to eq(reasons: ['invalid shape'])
    expect(error.details).to be_frozen
    expect(error.details[:reasons]).to be_frozen
    expect(error.details[:reasons].first).to be_frozen
  end

  it 'reports requested and maximum values without model output' do
    error = ZuQL::InterpretationLimitError.new(requested: 10_001, maximum: 10_000)

    expect(error.message).to eq('Requested result limit exceeds the configured maximum')
    expect(error.details).to eq(requested: 10_001, maximum: 10_000)
  end
end
