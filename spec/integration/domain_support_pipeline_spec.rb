# frozen_string_literal: true

RSpec.describe 'advertised MVP domain support' do
  it 'runs every representative question through the complete safe pipeline' do
    provider = ZuQL::Providers::FixtureProvider.from_yaml
    pipeline = ZuQL::Pipeline.new(interpreter: ZuQL::NaturalLanguageInterpreter.new(provider: provider))
    results = ZuQL::DomainSupportRegistry.new.domains.flat_map do |domain|
      domain.fetch('representative_questions').map do |question|
        [domain.fetch('id'), question, pipeline.call(question)]
      end
    end

    expect(results.size).to be >= 14
    expect(results.map(&:first).uniq).to contain_exactly(
      'subscriptions', 'product_catalog', 'orders', 'invoicing',
      'payments', 'credit_memos', 'debit_memos', 'usage'
    )
    results.each do |domain, question, result|
      expect(result.compiled_query.backend).to eq('data_query'), "#{domain}: #{question}"
      expect(result.compiled_query.sql).to start_with("SELECT\n"), "#{domain}: #{question}"
      expect(result.compiled_query.sql).to include("\nLIMIT "), "#{domain}: #{question}"
    end
  end
end
