# frozen_string_literal: true

RSpec.describe 'ZuQL contracts' do
  let(:query_spec) do
    {
      intent: 'detail_export', requested_entities: %w[account subscription],
      requested_fields: [{ concept: 'account name' }],
      filters: [{ concept: 'subscription status', operator: 'equals', value: 'Active' }],
      metrics: [], dimensions: [], group_by: [], order_by: [], limit: 1000,
      backend_preference: 'auto'
    }
  end

  it 'constructs immutable QuerySpec values and round trips JSON' do
    contract = ZuQL::Contracts::QuerySpec.from_h(query_spec.transform_keys(&:to_s))
    expect(contract).to be_frozen
    expect(contract.attributes).to be_frozen
    expect(contract.requested_fields.first.attributes).to be_frozen
    expect(described_class = ZuQL::Contracts::QuerySpec.from_json(contract.to_json)).to eq(contract)
    expect(described_class.to_h[:limit]).to eq(1000)
  end

  it 'rejects invalid and unknown QuerySpec input with a typed error' do
    expect { ZuQL::Contracts::QuerySpec.from_h(query_spec.merge(limit: 0)) }
      .to raise_error(ZuQL::ContractError)
    expect { ZuQL::Contracts::QuerySpec.from_h(query_spec.merge(sql: 'DROP TABLE account')) }
      .to raise_error(ZuQL::ContractError)
  end

  it 'rejects malformed JSON with a serialization error' do
    expect { ZuQL::Contracts::QuerySpec.from_json('{') }
      .to raise_error(ZuQL::SerializationError)
  end

  it 'constructs strict model query intent without application-controlled fields' do
    model_intent = {
      intent: 'detail_export', requested_entities: ['subscription'],
      requested_fields: [{ concept: 'subscription status' }],
      filters: [], metrics: [], dimensions: [], requested_limit: 25
    }

    contract = ZuQL::Contracts::ModelQueryIntent.from_h(model_intent)

    expect(contract.requested_limit).to eq(25)
    expect(contract).to be_frozen
    expect { ZuQL::Contracts::ModelQueryIntent.from_h(model_intent.merge(sql: 'SELECT 1')) }
      .to raise_error(ZuQL::ContractError)
  end

  it 'allows model query intent to omit its requested limit' do
    contract = ZuQL::Contracts::ModelQueryIntent.from_h(
      intent: 'count', requested_entities: ['subscription'], requested_fields: [],
      filters: [], metrics: [], dimensions: []
    )

    expect(contract.requested_limit).to be_nil
  end

  it 'allows scalar filter values and rejects structured model filter values' do
    attributes = {
      intent: 'detail_export', requested_entities: ['subscription'], requested_fields: [],
      filters: [{ concept: 'status', operator: 'in', value: ['Active', nil, 1, true] }],
      metrics: [], dimensions: []
    }

    expect(ZuQL::Contracts::ModelQueryIntent.from_h(attributes).filters.first.value)
      .to eq(['Active', nil, 1, true])
    expect do
      ZuQL::Contracts::ModelQueryIntent.from_h(
        attributes.merge(filters: [{ concept: 'status', operator: 'equals', value: { sql: 'DROP' } }])
      )
    end.to raise_error(ZuQL::ContractError)
  end

  it 'constructs extraction contracts with nested fields' do
    source = ZuQL::Contracts::ExtractedDataSource.from_h(
      name: 'Rate Plan Charge', url: 'https://docs.zuora.com/rpc', source_order: 1,
      feature_notes: ['Orders'], availability_notes: []
    )
    field = ZuQL::Contracts::ExtractedField.from_h(
      display_name: 'MRR', source_type: 'decimal', description: 'Monthly recurring revenue', source_order: 1
    )
    object = ZuQL::Contracts::ExtractedObject.from_h(label: 'Rate Plan Charge', role: 'base', fields: [field.to_h])
    expect(source.name).to eq('Rate Plan Charge')
    expect(object.fields.first).to eq(field)
  end

  it 'constructs canonical contracts and rejects invalid relationships' do
    object = ZuQL::Contracts::CanonicalObject.from_h(
      id: 'subscription', display_name: 'Subscription', description: 'Agreement',
      primary_key: 'id', default_grain: 'subscription', aliases: ['contract'], sources: []
    )
    field = ZuQL::Contracts::CanonicalField.from_h(
      id: 'subscription.status', object_id: 'subscription', canonical_name: 'status',
      display_name: 'Status', canonical_type: 'string', description: 'Lifecycle',
      semantic_type: 'status', aliases: [], filterable: true, selectable: true, sources: []
    )
    expect(object.id).to eq('subscription')
    expect(field.object_id).to eq(object.id)
    expect do
      ZuQL::Contracts::CanonicalRelationship.from_h(
        id: 'subscription.rate_plans', from_object: 'subscription', to_object: 'rate_plan',
        from_field: 'id', to_field: 'subscription_id', cardinality: 'many_to_everything',
        default_join_type: 'inner', fanout_risk: 'low', confidence: 'reviewed', sources: []
      )
    end.to raise_error(ZuQL::ContractError)
  end

  it 'constructs ResolvedQuery and QueryPlan without raw SQL' do
    resolved = ZuQL::Contracts::ResolvedQuery.from_h(
      query_spec: query_spec, resolutions: [{ input: 'account name', resolved_to: 'account.name',
                                              kind: 'field', confidence: 1.0, alternatives: [] }], warnings: []
    )
    plan = ZuQL::Contracts::QueryPlan.from_h(
      backend: 'data_query', root_object: 'subscription',
      select: [{ field: 'account.name', alias: 'account_name' }],
      joins: [{ relationship: 'account.subscriptions', join_type: 'inner' }],
      filters: [{ field: 'subscription.status', operator: '=', value: 'Active' }],
      group_by: [], order_by: [], limit: 1000, grain: 'subscription', warnings: []
    )
    expect(resolved.resolutions.first.resolved_to).to eq('account.name')
    expect(ZuQL::Contracts::QueryPlan.from_json(plan.to_json)).to eq(plan)
  end

  it 'constructs an immutable compiled query with mapping warnings' do
    compiled = ZuQL::Contracts::CompiledQuery.from_h(
      backend: 'data_query', sql: 'SELECT Account.ID FROM Account LIMIT 1',
      warnings: ['Account physical name is convention-derived.']
    )

    expect(compiled).to be_frozen
    expect(ZuQL::Contracts::CompiledQuery.from_json(compiled.to_json)).to eq(compiled)
  end

  it 'round trips a deeply immutable pipeline result' do
    result = pipeline_result
    round_trip = ZuQL::Contracts::PipelineResult.from_json(result.to_json)

    expect(round_trip).to eq(result)
  end

  it 'deeply freezes every pipeline result layer' do
    result = pipeline_result
    values = [result, result.attributes, result.plan.attributes, result.plan.select,
              result.plan.select.first.attributes, result.compiled_query.sql, result.explanation.joins]

    expect(values).to all(be_frozen)
  end

  it 'defensively copies every caller-owned pipeline result value' do
    attributes = JSON.parse(File.read('spec/fixtures/contracts/pipeline_result.json'), symbolize_names: true)
    result = ZuQL::Contracts::PipelineResult.from_h(attributes)

    attributes[:question] << ' changed'
    attributes[:warnings].first << ' changed'
    attributes[:plan][:root_object] << '_changed'

    expect(result.question).to eq('List subscriptions')
    expect(result.warnings).to eq(['mapping warning'])
    expect(result.plan.root_object).to eq('subscription')
    expect { result.attributes[:question] = 'forged' }.to raise_error(FrozenError)
    expect { result.explanation.summary << ' changed' }.to raise_error(FrozenError)
  end

  it 'deep-copies and deep-freezes compiled SQL and warnings' do
    sql = +'SELECT 1'
    warning = +'mapping warning'
    warnings = [warning]
    compiled = ZuQL::Contracts::CompiledQuery.from_h(
      backend: 'data_query', sql: sql, warnings: warnings
    )

    expect { compiled.sql << '; DROP TABLE Account' }.to raise_error(FrozenError)
    expect { compiled.warnings << 'another warning' }.to raise_error(FrozenError)
    expect { compiled.warnings.first << ' changed' }.to raise_error(FrozenError)
    expect(sql).to eq('SELECT 1')
    expect(warning).to eq('mapping warning')
    expect(warnings).to eq(['mapping warning'])
  end

  def pipeline_result
    attributes = JSON.parse(File.read('spec/fixtures/contracts/pipeline_result.json'), symbolize_names: true)
    ZuQL::Contracts::PipelineResult.from_h(attributes)
  end
end
