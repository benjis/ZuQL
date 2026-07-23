# frozen_string_literal: true

require 'zuql'

RSpec.describe ZuQL::DataQueryCompiler do
  subject(:compiler) { described_class.new }

  let(:aggregate_plan) do
    query_plan(
      root_object: 'rate_plan_charge',
      select: [
        { field: 'account.name', alias: 'account' },
        { metric: 'current_mrr', alias: 'current_mrr' }
      ],
      joins: [
        { relationship: 'rate_plan.rate_plan_charge', join_type: 'inner' },
        { relationship: 'subscription.rate_plan', join_type: 'inner' },
        { relationship: 'account.subscription', join_type: 'inner' }
      ],
      group_by: ['account.name'], order_by: [{ field: 'current_mrr', direction: 'desc' }],
      grain: 'rate_plan_charge'
    )
  end

  def query_plan(overrides = {})
    ZuQL::Contracts::QueryPlan.from_h(
      {
        backend: 'data_query', root_object: 'subscription',
        select: [{ field: 'subscription.name', alias: 'subscription_name' }],
        joins: [], filters: [], group_by: [], order_by: [], limit: 100,
        grain: 'subscription', warnings: []
      }.merge(overrides)
    )
  end

  it 'compiles a deterministic detail query' do
    compiled = compiler.compile(query_plan)

    expect(compiled.sql).to eq(<<~SQL.chomp)
      SELECT
        "subscription"."Name" AS "subscription_name"
      FROM "Subscription" AS "subscription"
      LIMIT 100
    SQL
    expect(compiled.backend).to eq('data_query')
    expect(compiled).to be_frozen
    expect(compiler.compile(query_plan).to_json).to eq(compiled.to_json)
  end

  it 'compiles aggregate functions, inverse bridge joins, grouping, and ordering' do
    expect(compiler.compile(aggregate_plan).sql).to eq(<<~SQL.chomp)
      SELECT
        "account"."Name" AS "account",
        SUM("rate_plan_charge"."MRR") AS "current_mrr"
      FROM "RatePlanCharge" AS "rate_plan_charge"
      INNER JOIN "RatePlan" AS "rate_plan" ON "rate_plan"."ID" = "rate_plan_charge"."ratePlanId"
      INNER JOIN "Subscription" AS "subscription" ON "subscription"."ID" = "rate_plan"."subscriptionId"
      INNER JOIN "Account" AS "account" ON "account"."ID" = "subscription"."accountId"
      GROUP BY "account"."Name"
      ORDER BY "current_mrr" DESC
      LIMIT 100
    SQL
  end

  it 'compiles COUNT DISTINCT metrics' do
    plan = query_plan(
      select: [{ metric: 'subscription_count', alias: 'subscription_count' }]
    )

    expect(compiler.compile(plan).sql).to include(
      'COUNT(DISTINCT "subscription"."ID") AS "subscription_count"'
    )
  end

  it 'compiles forward joins and preserves LEFT JOIN' do
    plan = query_plan(
      root_object: 'account', select: [{ field: 'subscription.name', alias: 'subscription_name' }],
      joins: [{ relationship: 'account.subscription', join_type: 'left' }], grain: 'account'
    )

    expect(compiler.compile(plan).sql).to include(
      'LEFT JOIN "Subscription" AS "subscription" ON "account"."ID" = "subscription"."accountId"'
    )
  end

  it 'compiles scalar, NULL, set, and contains filters' do
    plan = query_plan(
      filters: [
        { field: 'subscription.status', operator: '=', value: 'Active' },
        { field: 'subscription.term_start_date', operator: '>=', value: '2026-01-01' },
        { field: 'subscription.auto_renew', operator: '=', value: true },
        { field: 'subscription.cancelled_date', operator: '!=', value: nil },
        { field: 'subscription.status', operator: 'IN', value: %w[Active Pending] },
        { field: 'subscription.name', operator: 'LIKE', value: 'ACME_50%' }
      ]
    )

    expect(compiler.compile(plan).sql).to include(<<~SQL.chomp)
      WHERE "subscription"."Status" = 'Active'
        AND "subscription"."TermStartDate" >= '2026-01-01'
        AND "subscription"."AutoRenew" = TRUE
        AND "subscription"."CancelledDate" IS NOT NULL
        AND "subscription"."Status" IN ('Active', 'Pending')
        AND "subscription"."Name" LIKE '%ACME\\_50\\%%' ESCAPE '\\'
    SQL
  end

  it 'returns one stable warning for every convention-derived object mapping' do
    plan = query_plan(
      select: [{ field: 'account.name', alias: 'account_name' }],
      joins: [{ relationship: 'account.subscription', join_type: 'inner' }],
      warnings: ['MRR is not recognized revenue.']
    )

    expect(compiler.compile(plan).warnings).to eq(
      [
        'MRR is not recognized revenue.',
        'Data Query object subscription uses convention-derived physical name Subscription.',
        'Data Query object account uses convention-derived physical name Account.'
      ]
    )
  end

  it 'rejects a non-plan input and a plan for another backend' do
    expect { compiler.compile({}) }.to raise_error(ZuQL::CompilationError)
    expect { compiler.compile(query_plan(backend: 'snowflake')) }
      .to raise_error(ZuQL::CompilationError) { |error| expect(error.details).to include(backend: 'snowflake') }
  end

  it 'rejects unknown fields, metrics, and unapproved relationships' do
    expect { compiler.compile(query_plan(select: [{ field: 'subscription.made_up', alias: 'bad' }])) }
      .to raise_error(ZuQL::CompilationError)
    expect { compiler.compile(query_plan(select: [{ metric: 'made_up', alias: 'bad' }])) }
      .to raise_error(ZuQL::CompilationError)
    expect do
      compiler.compile(
        query_plan(joins: [{ relationship: 'payment.payment_part', join_type: 'inner' }])
      )
    end.to raise_error(ZuQL::CompilationError)
  end

  it 'rejects disconnected, out-of-order, and duplicate joins' do
    disconnected = query_plan(
      joins: [{ relationship: 'invoice.invoice_item', join_type: 'inner' }]
    )
    duplicate = query_plan(
      joins: [
        { relationship: 'account.subscription', join_type: 'inner' },
        { relationship: 'account.subscription', join_type: 'inner' }
      ]
    )

    expect { compiler.compile(disconnected) }.to raise_error(ZuQL::CompilationError, /join/i)
    expect { compiler.compile(duplicate) }.to raise_error(ZuQL::CompilationError, /join/i)
  end

  it 'allows ordering only by a selected alias and a valid direction' do
    unknown_alias = query_plan(order_by: [{ field: 'other', direction: 'asc' }])
    bad_direction = query_plan(order_by: [{ field: 'subscription_name', direction: 'sideways' }])
    extra_key = query_plan(order_by: [{ field: 'subscription_name', direction: 'asc', sql: 'DROP' }])

    expect { compiler.compile(unknown_alias) }.to raise_error(ZuQL::CompilationError)
    expect { compiler.compile(bad_direction) }.to raise_error(ZuQL::CompilationError)
    expect { compiler.compile(extra_key) }.to raise_error(ZuQL::CompilationError)
  end

  it 'rejects unsupported metric aggregations' do
    registry_class = Class.new(ZuQL::DataQueryRegistry) do
      def metric(id)
        super.merge(aggregation: 'average')
      end
    end
    custom_compiler = described_class.new(registry: registry_class.new)
    plan = query_plan(select: [{ metric: 'subscription_count', alias: 'subscription_count' }])

    expect { custom_compiler.compile(plan) }
      .to raise_error(ZuQL::CompilationError, /aggregation/i)
  end

  it 'rejects aggregate fields that are absent from GROUP BY' do
    missing_group = query_plan(
      select: [
        { field: 'subscription.name', alias: 'subscription_name' },
        { metric: 'subscription_count', alias: 'subscription_count' }
      ]
    )

    expect { compiler.compile(missing_group) }
      .to raise_error(ZuQL::CompilationError, /group/i)
  end

  it 'rejects duplicate selection aliases' do
    duplicate_alias = query_plan(
      select: [
        { field: 'subscription.name', alias: 'duplicate' },
        { field: 'subscription.status', alias: 'duplicate' }
      ]
    )

    expect { compiler.compile(duplicate_alias) }
      .to raise_error(ZuQL::CompilationError, /alias/i)
  end

  it 'quotes reserved physical names and aliases for the Order object' do
    order_plan = query_plan(
      root_object: 'order', select: [{ field: 'order.id', alias: 'order_id' }],
      grain: 'order'
    )

    expect(compiler.compile(order_plan).sql).to eq(<<~SQL.chomp)
      SELECT
        "order"."ID" AS "order_id"
      FROM "Order" AS "order"
      LIMIT 100
    SQL
  end

  domain_cases = {
    'subscription' => 'subscription.name',
    'account' => 'account.account_number',
    'product' => 'product.name',
    'product_rate_plan' => 'product_rate_plan.name',
    'product_rate_plan_charge' => 'product_rate_plan_charge.default_quantity',
    'order' => 'order.order_number',
    'invoice' => 'invoice.id',
    'invoice_item' => 'invoice_item.charge_amount',
    'payment' => 'payment.amount',
    'credit_memo' => 'credit_memo.id',
    'debit_memo' => 'debit_memo.id',
    'usage' => 'usage.quantity'
  }

  domain_cases.each do |object_id, field_id|
    it "compiles a registry-bound detail shape for the #{object_id} domain" do
      plan = query_plan(
        root_object: object_id, select: [{ field: field_id, alias: 'value' }], grain: object_id
      )

      sql = compiler.compile(plan).sql
      expect(sql).to include('FROM "').and include("\" AS \"#{object_id}\"")
      expect(sql).to include("\"#{object_id}\"").and end_with('LIMIT 100')
    end
  end

  it 'rejects compiler limits above the documented maximum' do
    expect { compiler.compile(query_plan(limit: 10_001)) }
      .to raise_error(ZuQL::CompilationError) { |error| expect(error.details).to include(kind: 'limit') }
  end

  it 'rejects invalid compiler limit configuration' do
    expect { described_class.new(max_limit: 0) }.to raise_error(ZuQL::CompilationError, /limit/i)
  end

  it 'rejects empty selections' do
    expect { compiler.compile(query_plan(select: [])) }
      .to raise_error(ZuQL::CompilationError, /selection/i)
  end

  it 'rejects grouping without a metric' do
    expect { compiler.compile(query_plan(group_by: ['subscription.name'])) }
      .to raise_error(ZuQL::CompilationError, /group/i)
  end

  it 'rejects duplicate and unselected grouping fields' do
    aggregate = [{ metric: 'subscription_count', alias: 'count' }]
    duplicate = query_plan(select: aggregate, group_by: ['subscription.name', 'subscription.name'])
    unselected = query_plan(select: aggregate, group_by: ['subscription.name'])

    expect { compiler.compile(duplicate) }.to raise_error(ZuQL::CompilationError, /group/i)
    expect { compiler.compile(unselected) }.to raise_error(ZuQL::CompilationError, /group/i)
  end

  it 'rejects mutable and dynamically-dispatched plans' do
    mutable = ZuQL::Contracts::QueryPlan.new(query_plan.to_h)
    dynamic = ZuQL::Contracts::QueryPlan.new(query_plan.to_h)
    dynamic.define_singleton_method(:limit) { 1 }
    dynamic.freeze

    expect { compiler.compile(mutable) }.to raise_error(ZuQL::CompilationError)
    expect { compiler.compile(dynamic) }.to raise_error(ZuQL::CompilationError)
  end

  it 'rejects invalid NULL and set filter shapes' do
    null_range = query_plan(filters: [{ field: 'subscription.name', operator: '>', value: nil }])
    empty_set = query_plan(filters: [{ field: 'subscription.name', operator: 'IN', value: [] }])
    null_set = query_plan(filters: [{ field: 'subscription.name', operator: 'IN', value: ['A', nil] }])

    [null_range, empty_set, null_set].each do |plan|
      expect { compiler.compile(plan) }.to raise_error(ZuQL::CompilationError, /filter/i)
    end
  end

  it 'rejects non-selectable and non-filterable registry fields' do
    registry_class = Class.new(ZuQL::DataQueryRegistry) do
      def field(id)
        metadata = super
        return metadata.merge(selectable: false) if id == 'subscription.name'

        metadata
      end
    end
    filter_registry_class = Class.new(ZuQL::DataQueryRegistry) do
      def field(id)
        metadata = super
        return metadata.merge(filterable: false) if id == 'subscription.status'

        metadata
      end
    end

    expect { described_class.new(registry: registry_class.new).compile(query_plan) }
      .to raise_error(ZuQL::CompilationError, /selection/i)
    filtered = query_plan(filters: [{ field: 'subscription.status', operator: '=', value: 'Active' }])
    expect { described_class.new(registry: filter_registry_class.new).compile(filtered) }
      .to raise_error(ZuQL::CompilationError, /filter/i)
  end

  it 'rejects unsupported registered field types during filtering' do
    registry_class = Class.new(ZuQL::DataQueryRegistry) do
      def field(id)
        super.merge(type: 'json')
      end
    end
    plan = query_plan(filters: [{ field: 'subscription.status', operator: '=', value: 'Active' }])

    expect { described_class.new(registry: registry_class.new).compile(plan) }
      .to raise_error(ZuQL::CompilationError, /type/i)
  end
end
