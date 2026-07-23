# frozen_string_literal: true

RSpec.describe ZuQL::MetadataRetriever do
  subject(:retriever) { described_class.new }

  it 'returns bounded relevant metadata and nearby relationships deterministically' do # rubocop:disable RSpec/MultipleExpectations
    first = retriever.retrieve('Show monthly recurring revenue by customer account')
    second = retriever.retrieve('Show monthly recurring revenue by customer account')

    expect(first).to eq(second)
    expect(first).to be_frozen
    expect(first.fetch(:metrics).map { |item| item.fetch('id') }).to include('current_mrr')
    expect(first.fetch(:dimensions).map { |item| item.fetch('id') }).to include('account')
    expect(first.fetch(:objects).length).to be <= 8
    expect(first.fetch(:fields).length).to be <= 24
    expect(first.fetch(:relationships).length).to be <= 12
  end

  it 'does not send the whole registry for an unknown concept' do
    context = retriever.retrieve('quantum aardvark velocity')

    expect(context.fetch(:objects)).to be_empty
    expect(context.fetch(:fields)).to be_empty
    expect(context.fetch(:metrics)).to be_empty
    expect(context.fetch(:dimensions)).to be_empty
    expect(context.fetch(:relationships)).to be_empty
  end
end
