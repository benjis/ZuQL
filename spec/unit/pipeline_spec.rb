# frozen_string_literal: true

RSpec.describe ZuQL::Pipeline do
  let(:query_spec) do
    ZuQL::Contracts::QuerySpec.from_h(intent: 'count', requested_entities: ['Subscription'], requested_fields: [],
                                      filters: [], metrics: ['subscription count'], dimensions: [], group_by: [],
                                      order_by: [], limit: 1000, backend_preference: 'auto')
  end
  let(:resolution) do
    { input: 'Subscription', resolved_to: 'subscription', kind: 'object', confidence: 1.0, alternatives: [] }
  end
  let(:resolved) do
    ZuQL::Contracts::ResolvedQuery.from_h(query_spec: query_spec, resolutions: [resolution], warnings: %w[A B])
  end
  let(:plan) do
    ZuQL::Contracts::QueryPlan.from_h(backend: 'data_query', root_object: 'subscription',
                                      select: [{ metric: 'subscription_count', alias: 'count' }],
                                      joins: [], filters: [],
                                      group_by: [], order_by: [], limit: 1000, grain: 'subscription', warnings: %w[B C])
  end
  let(:artifacts) do
    {
      compiled: ZuQL::Contracts::CompiledQuery.from_h(backend: 'data_query', sql: 'untrusted', warnings: []),
      trusted: ZuQL::Contracts::CompiledQuery.from_h(backend: 'data_query', sql: 'trusted', warnings: %w[C D]),
      explanation: ZuQL::Contracts::QueryExplanation.from_h(
        summary: 'summary', resolutions: ['resolution'], root: 'root', joins: ['No joins required.'],
        grain: 'grain', grouping: 'No grouping.'
      )
    }
  end

  it 'runs stages in order, retaining only the validated query and stable warnings' do
    events = []
    pipeline = described_class.new(
      interpreter: recording_stage(events, :interpret, query_spec),
      resolver: recording_stage(events, :resolve, resolved), planner: recording_stage(events, :plan, plan),
      compiler: recording_stage(events, :compile, artifacts[:compiled]),
      validator: recording_stage(events, :validate!, artifacts[:trusted]),
      explainer: recording_stage(events, :explain, artifacts[:explanation])
    )

    result = pipeline.call('Count active subscriptions')

    expect(events).to eq(%i[interpret resolve plan compile validate! explain])
    expect(result.compiled_query.sql).to eq('trusted')
    expect(result.warnings).to eq(%w[A B C D])
  end

  it 'propagates domain failures without calling later stages' do
    error = ZuQL::ResolutionError.new('failed')
    query_spec_value = query_spec
    compiled_value = artifacts[:compiled]
    trusted_value = artifacts[:trusted]
    resolver = Object.new.tap { |object| object.define_singleton_method(:resolve) { |_| raise error } }
    forbidden = Object.new.tap { |object| object.define_singleton_method(:plan) { |_| raise 'called' } }
    pipeline = described_class.new(
      interpreter: Object.new.tap { |o| o.define_singleton_method(:interpret) { |_| query_spec_value } },
      resolver: resolver, planner: forbidden,
      compiler: Object.new.tap { |o| o.define_singleton_method(:compile) { |_| compiled_value } },
      validator: Object.new.tap { |o| o.define_singleton_method(:validate!) { |*| trusted_value } },
      explainer: ZuQL::QueryExplainer.new
    )

    expect { pipeline.call('question') }.to(raise_error { |raised| expect(raised).to equal(error) })
  end

  it 'validates collaborator interfaces eagerly' do
    expect do
      described_class.new(interpreter: Object.new, resolver: Object.new, planner: Object.new,
                          compiler: Object.new, validator: Object.new, explainer: Object.new)
    end.to raise_error(ArgumentError)
  end

  def recording_stage(events, method, value)
    Object.new.tap do |object|
      object.define_singleton_method(method) do |*, **|
        events << method
        value
      end
    end
  end
end
