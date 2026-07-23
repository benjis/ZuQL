# frozen_string_literal: true

RSpec.describe ZuQL::QueryExplainer do
  subject(:explainer) { described_class.new }

  let(:query_spec) do
    ZuQL::Contracts::QuerySpec.from_h(
      intent: 'count', requested_entities: ['Subscription'], requested_fields: [], filters: [],
      metrics: ['subscription count'], dimensions: [], group_by: [], order_by: [], limit: 1000,
      backend_preference: 'auto'
    )
  end
  let(:resolution) do
    { input: 'Subscription', resolved_to: 'subscription', kind: 'object', confidence: 1.0, alternatives: [] }
  end
  let(:resolved_query) do
    ZuQL::Contracts::ResolvedQuery.from_h(query_spec: query_spec, resolutions: [resolution], warnings: [])
  end
  let(:plan) do
    ZuQL::Contracts::QueryPlan.from_h(
      backend: 'data_query', root_object: 'subscription', select: [{ metric: 'subscription_count', alias: 'count' }],
      joins: [], filters: [], group_by: [], order_by: [], limit: 1000, grain: 'subscription', warnings: []
    )
  end
  let(:compiled_query) do
    ZuQL::Contracts::CompiledQuery.from_h(backend: 'data_query', sql: 'SELECT 1', warnings: [])
  end

  def explain(query_spec: self.query_spec, resolved_query: self.resolved_query, plan: self.plan)
    explainer.explain(
      query_spec: query_spec, resolved_query: resolved_query, plan: plan, compiled_query: compiled_query
    )
  end

  it 'explains a no-join query deterministically' do
    explanation = explain

    expect(explanation.summary).to eq('Intent count on data_query, rooted at subscription, limit 1000.')
    expect(explanation.resolutions).to eq(['Subscription → subscription (object, confidence 1.0).'])
    expect(explanation.root).to eq('Planner selected subscription as the root object.')
    expect(explanation.joins).to eq(['No joins required.'])
    expect(explanation.grain).to eq('Result grain: subscription.')
    expect(explanation.grouping).to eq('No grouping.')
  end

  it 'explains joins and grouping in artifact order' do
    joined = ZuQL::Contracts::QueryPlan.from_h(
      plan.to_h.merge(joins: [{ relationship: 'account.subscription', join_type: 'inner' }],
                      group_by: ['account.name'])
    )
    explanation = explain(plan: joined)

    expect(explanation.joins).to eq(['INNER JOIN via account.subscription.'])
    expect(explanation.grouping).to eq('Grouped by: account.name.')
  end

  it 'rejects untyped and extended contract inputs' do
    subclass = Class.new(ZuQL::Contracts::QuerySpec).new(query_spec.to_h)
    singleton = ZuQL::Contracts::QueryPlan.new(plan.to_h)
    singleton.define_singleton_method(:tampered?) { true }
    singleton.freeze

    expect { explain(query_spec: {}) }
      .to raise_error(ZuQL::ContractError)
    expect { explain(query_spec: subclass) }
      .to raise_error(ZuQL::ContractError)
    expect { explain(plan: singleton) }
      .to raise_error(ZuQL::ContractError)
  end

  it 'rejects a contract that hides its singleton methods' do
    forged = ZuQL::Contracts::QuerySpec.new(query_spec.to_h)
    forged.define_singleton_method(:singleton_methods) { [] }
    forged.freeze

    expect { explain(query_spec: forged) }
      .to raise_error(ZuQL::ContractError)
  end

  it 'rejects nested contracts with forged accessors' do
    forged_resolution = ZuQL::Contracts::Resolution.new(resolution)
    forged_resolution.define_singleton_method(:input) { 'FORGED INPUT' }
    forged = ZuQL::Contracts::ResolvedQuery.new(
      query_spec: query_spec, resolutions: [forged_resolution], warnings: []
    )

    expect { explain(resolved_query: forged) }
      .to raise_error(ZuQL::ContractError)
  end
end
