# frozen_string_literal: true

require 'zuql'

RSpec.describe ZuQL::QueryPlanner do
  subject(:planner) { described_class.new }

  let(:resolver) { ZuQL::SemanticResolver.new }

  def resolved_query(overrides = {})
    query_spec = ZuQL::Contracts::QuerySpec.from_h(
      {
        intent: 'detail_export', requested_entities: [], requested_fields: [], filters: [],
        metrics: [], dimensions: [], group_by: [], order_by: [], limit: 1000,
        backend_preference: 'auto'
      }.merge(overrides)
    )
    resolver.resolve(query_spec)
  end

  it 'builds a detail plan rooted at the requested entity' do
    plan = planner.plan(
      resolved_query(
        requested_entities: ['Subscription'],
        requested_fields: [{ concept: 'subscription.name' }, { concept: 'account.name' }]
      )
    )

    expect(plan.root_object).to eq('subscription')
    expect(plan.grain).to eq('subscription')
    expect(plan.select.map(&:to_h)).to eq(
      [
        { field: 'subscription.name', alias: 'subscription_name' },
        { field: 'account.name', alias: 'account_name' }
      ]
    )
    expect(plan.joins.map(&:to_h)).to eq(
      [{ relationship: 'account.subscription', join_type: 'inner' }]
    )
  end

  it 'rejects aggregate metrics in a detail query' do
    query = resolved_query(
      requested_entities: ['Subscription'],
      requested_fields: [{ concept: 'subscription.name' }], metrics: ['MRR']
    )

    expect { planner.plan(query) }
      .to raise_error(ZuQL::InvalidQueryShapeError) do |error|
        expect(error.details).to include(intent: 'detail_export', reason: 'metrics_not_allowed')
      end
  end

  it 'inserts bridge objects and emits joins in deterministic traversal order' do
    plan = planner.plan(
      resolved_query(
        requested_entities: ['Account'],
        requested_fields: [{ concept: 'rate_plan_charge.name' }]
      )
    )

    expect(plan.joins.map(&:relationship)).to eq(
      %w[account.subscription subscription.rate_plan rate_plan.rate_plan_charge]
    )
  end

  it 'builds a safe aggregate plan at the metric native grain' do
    plan = planner.plan(
      resolved_query(intent: 'aggregate', metrics: ['MRR'], dimensions: ['Account'])
    )

    expect(plan.backend).to eq('data_query')
    expect(plan.root_object).to eq('rate_plan_charge')
    expect(plan.grain).to eq('rate_plan_charge')
    expect(plan.select.map(&:to_h)).to eq(
      [
        { field: 'account.name', alias: 'account' },
        { metric: 'current_mrr', alias: 'current_mrr' }
      ]
    )
    expect(plan.group_by).to eq(['account.name'])
    expect(plan.warnings).to include(/not recognized revenue/i)
  end

  it 'maps filters, explicit grouping, backend, ordering, and limit' do
    plan = planner.plan(
      resolved_query(
        intent: 'count', metrics: ['Subscription Count'], group_by: ['Subscription Status'],
        filters: [{ concept: 'Subscription Status', operator: 'equals', value: 'Active' }],
        backend_preference: 'snowflake', order_by: [{ field: 'subscription_status', direction: 'asc' }],
        limit: 25
      )
    )

    expect(plan.backend).to eq('snowflake')
    expect(plan.filters.map(&:to_h)).to eq(
      [{ field: 'subscription.status', operator: '=', value: 'Active' }]
    )
    expect(plan.group_by).to eq(['subscription.status'])
    expect(plan.order_by).to eq([{ field: 'subscription_status', direction: 'asc' }])
    expect(plan.limit).to eq(25)
  end

  it 'rejects operators that are incompatible with the resolved field type' do
    query = resolved_query(
      requested_entities: ['Prepaid Balance Fund'],
      requested_fields: [{ concept: 'prepaid_balance_fund.id' }],
      filters: [{ concept: 'prepaid_balance_fund.start_date', operator: 'contains', value: '2026' }]
    )

    expect { planner.plan(query) }
      .to raise_error(ZuQL::IncompatibleFilterError) do |error|
        expect(error.details).to include(
          field: 'prepaid_balance_fund.start_date', field_type: 'date',
          operator: 'contains', reason: 'contains_requires_string_field'
        )
      end
  end

  it 'rejects filter values that do not match the resolved numeric field type' do
    query = resolved_query(
      requested_entities: ['Prepaid Balance Fund'],
      requested_fields: [{ concept: 'prepaid_balance_fund.id' }],
      filters: [{ concept: 'prepaid_balance_fund.priority', operator: 'gte', value: 'high' }]
    )

    expect { planner.plan(query) }
      .to raise_error(ZuQL::IncompatibleFilterError) do |error|
        expect(error.details).to include(field_type: 'integer', reason: 'value_type_mismatch')
      end
  end

  it 'returns an immutable and deterministically serializable plan' do
    query = resolved_query(
      requested_entities: ['Subscription'], requested_fields: [{ concept: 'subscription.name' }]
    )

    first = planner.plan(query)
    second = planner.plan(query)

    expect(first).to be_frozen
    expect(first.to_json).to eq(second.to_json)
  end

  it 'fails with a typed error when no root object can be selected' do
    expect { planner.plan(resolved_query) }
      .to raise_error(ZuQL::MissingRootObjectError) do |error|
        expect(error.details).to eq(intent: 'detail_export')
      end
  end

  it 'fails when aggregate metrics have incompatible native grains' do
    query = resolved_query(
      intent: 'aggregate', metrics: ['MRR', 'Invoice Charge Amount']
    )

    expect { planner.plan(query) }
      .to raise_error(ZuQL::IncompatibleMetricGrainsError) do |error|
        expect(error.details.fetch(:metric_grains)).to eq(
          current_mrr: 'rate_plan_charge', invoice_charge_amount: 'invoice_item'
        )
      end
  end

  it 'rejects requested fields in aggregate queries instead of emitting invalid grouping' do
    query = resolved_query(
      intent: 'aggregate', requested_fields: [{ concept: 'subscription.name' }], metrics: ['MRR']
    )

    expect { planner.plan(query) }
      .to raise_error(ZuQL::InvalidQueryShapeError) do |error|
        expect(error.details).to include(intent: 'aggregate', reason: 'requested_fields_not_grouped')
      end
  end

  it 'rejects aggregate and count queries without a curated metric' do
    aggregate = resolved_query(intent: 'aggregate', dimensions: ['Account'])
    count = resolved_query(intent: 'count', requested_entities: ['Subscription'])

    expect { planner.plan(aggregate) }
      .to raise_error(ZuQL::InvalidQueryShapeError, /metric/i)
    expect { planner.plan(count) }
      .to raise_error(ZuQL::InvalidQueryShapeError, /metric/i)
  end

  it 'translates an unavailable approved path into a planning error' do
    query_spec = ZuQL::Contracts::QuerySpec.from_h(
      intent: 'aggregate', requested_entities: ['Payment Run'], requested_fields: [], filters: [],
      metrics: ['Payment Amount'], dimensions: [], group_by: [], order_by: [], limit: 1000,
      backend_preference: 'auto'
    )
    resolved = ZuQL::Contracts::ResolvedQuery.from_h(
      query_spec: query_spec,
      resolutions: [
        { input: 'Payment Amount', resolved_to: 'payment_amount', kind: 'metric', confidence: 1.0 },
        { input: 'Payment Run', resolved_to: 'payment_run', kind: 'object', confidence: 1.0 }
      ],
      warnings: []
    )

    expect { planner.plan(resolved) }
      .to raise_error(ZuQL::JoinPathError) do |error|
        expect(error.details).to include(root_object: 'payment', target_objects: include('payment_run'))
      end
  end

  safe_fanout_cases = [
    ['MRR', 'Account'],
    ['MRR', 'Subscription Status'],
    ['Invoice Charge Amount', 'Invoice Date'],
    ['Invoice Charge Amount', 'Account'],
    ['Payment Amount', 'Payment Date'],
    ['Subscription Count', 'Charge']
  ]

  safe_fanout_cases.each do |metric, dimension|
    it "accepts the safe fan-out scenario #{metric} by #{dimension}" do
      query = resolved_query(intent: 'aggregate', metrics: [metric], dimensions: [dimension])

      expect { planner.plan(query) }.not_to raise_error
    end
  end

  unsafe_fanout_cases = [
    ['MRR', 'Invoice Date'],
    ['MRR', 'Payment Date'],
    ['Invoice Charge Amount', 'Subscription Status'],
    ['Payment Amount', 'Invoice Date'],
    ['Invoice Balance', 'Charge'],
    ['Credit Memo Amount', 'Payment Date'],
    ['Debit Memo Amount', 'Subscription']
  ]

  unsafe_fanout_cases.each do |metric, dimension|
    it "rejects the unsafe fan-out scenario #{metric} by #{dimension}" do
      query = resolved_query(intent: 'aggregate', metrics: [metric], dimensions: [dimension])

      expect { planner.plan(query) }
        .to raise_error(ZuQL::FanoutRiskError) do |error|
          expect(error.details).to include(metric: kind_of(String), relationship: kind_of(String))
        end
    end
  end

  it 'reports only the path leading to the risky relationship' do
    query = resolved_query(
      intent: 'aggregate', metrics: ['MRR'], dimensions: ['Invoice Date', 'Payment Date']
    )

    expect { planner.plan(query) }
      .to raise_error(ZuQL::FanoutRiskError) do |error|
        expect(error.details.fetch(:path)).to eq(
          %w[
            rate_plan.rate_plan_charge subscription.rate_plan account.subscription
            account.invoice
          ]
        )
      end
  end
end
