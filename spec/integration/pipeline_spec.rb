# frozen_string_literal: true

RSpec.describe 'offline query pipeline' do
  it 'compiles and validates the active subscription example' do
    provider = ZuQL::Providers::FixtureProvider.from_yaml
    pipeline = ZuQL::Pipeline.new(interpreter: ZuQL::NaturalLanguageInterpreter.new(provider: provider))

    result = pipeline.call('Count active subscriptions')

    expect(result.plan.root_object).to eq('subscription')
    expect(result.plan.joins).to eq([])
    expect(result.compiled_query.backend).to eq('data_query')
    expect(result.compiled_query.sql).to include('COUNT(DISTINCT')
    expect(result.compiled_query.sql).to include('LIMIT 1000')
  end
end
