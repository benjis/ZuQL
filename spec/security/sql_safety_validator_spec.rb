# frozen_string_literal: true

require 'zuql'

RSpec.describe 'SQL safety mutation corpus' do
  subject(:validator) { ZuQL::SqlSafetyValidator.new }

  let(:compiler) { ZuQL::DataQueryCompiler.new }
  let(:plan) do
    ZuQL::Contracts::QueryPlan.from_h(
      backend: 'data_query', root_object: 'rate_plan_charge',
      select: [
        { field: 'account.name', alias: 'account' },
        { metric: 'current_mrr', alias: 'current_mrr' }
      ],
      joins: [
        { relationship: 'rate_plan.rate_plan_charge', join_type: 'inner' },
        { relationship: 'subscription.rate_plan', join_type: 'inner' },
        { relationship: 'account.subscription', join_type: 'inner' }
      ],
      filters: [{ field: 'subscription.status', operator: '=', value: 'Active' }],
      group_by: ['account.name'], order_by: [{ field: 'current_mrr', direction: 'desc' }],
      limit: 100, grain: 'rate_plan_charge', warnings: ['MRR is not recognized revenue.']
    )
  end
  let(:compiled_query) { compiler.compile(plan) }

  sql_mutations = {
    'appended DELETE statement' => ->(sql) { "#{sql}; DELETE FROM Account" },
    'appended DROP statement' => ->(sql) { "#{sql}; DROP TABLE Account" },
    'prepended CREATE statement' => ->(sql) { "CREATE TABLE x (id bigint); #{sql}" },
    'prepended block comment' => ->(sql) { "/* hidden */ #{sql}" },
    'appended line comment' => ->(sql) { "#{sql} -- hidden" },
    'changed table' => ->(sql) { sql.sub('"RatePlanCharge"', '"Payment"') },
    'changed column' => ->(sql) { sql.sub('"MRR"', '"Amount"') },
    'changed JOIN type' => ->(sql) { sql.sub('INNER JOIN', 'CROSS JOIN') },
    'changed filter value' => ->(sql) { sql.sub("'Active'", "'Cancelled'") },
    'changed aggregation' => ->(sql) { sql.sub('SUM(', 'MAX(') },
    'changed ordering' => ->(sql) { sql.sub('DESC', 'ASC') },
    'changed limit' => ->(sql) { sql.sub('LIMIT 100', 'LIMIT 10000') },
    'removed grouping' => ->(sql) { sql.lines.reject { |line| line.start_with?('GROUP BY') }.join.chomp },
    'changed whitespace' => ->(sql) { "#{sql}\n" }
  }

  sql_mutations.each do |label, mutate|
    it "rejects #{label}" do
      forged = ZuQL::Contracts::CompiledQuery.from_h(
        backend: 'data_query', sql: mutate.call(compiled_query.sql), warnings: compiled_query.warnings
      )

      expect { validator.validate!(plan, forged) }
        .to raise_error(ZuQL::SafetyValidationError) do |error|
          expect(error.details).to eq(reason: 'compiled_query_mismatch')
          expect(error.message).not_to include(forged.sql)
        end
    end
  end

  it 'rejects warning removal or injection' do
    removed = ZuQL::Contracts::CompiledQuery.from_h(
      backend: 'data_query', sql: compiled_query.sql, warnings: []
    )
    injected = ZuQL::Contracts::CompiledQuery.from_h(
      backend: 'data_query', sql: compiled_query.sql, warnings: compiled_query.warnings + ['safe']
    )

    expect { validator.validate!(plan, removed) }.to raise_error(ZuQL::SafetyValidationError)
    expect { validator.validate!(plan, injected) }.to raise_error(ZuQL::SafetyValidationError)
  end

  it 'continues to accept the unmodified compiler artifact' do
    validated = validator.validate!(plan, compiled_query)

    expect(validated).not_to equal(compiled_query)
    expect(validated.to_h).to eq(compiled_query.to_h)
  end
end
