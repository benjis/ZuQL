# frozen_string_literal: true

require 'zuql'

RSpec.describe ZuQL::SqlSafetyValidator do
  subject(:validator) { described_class.new }

  let(:compiler) { ZuQL::DataQueryCompiler.new }
  let(:plan) do
    ZuQL::Contracts::QueryPlan.from_h(
      backend: 'data_query', root_object: 'subscription',
      select: [{ field: 'subscription.name', alias: 'subscription_name' }],
      joins: [], filters: [], group_by: [], order_by: [], limit: 100,
      grain: 'subscription', warnings: ['Public schema mapping is unverified.']
    )
  end
  let(:compiled_query) { compiler.compile(plan) }

  def replace_plan(original, overrides)
    ZuQL::Contracts::QueryPlan.from_h(original.to_h.merge(overrides))
  end

  it 'returns a freshly recompiled trusted artifact' do
    validated = validator.validate!(plan, compiled_query)

    expect(validated).not_to equal(compiled_query)
    expect(validated.to_h).to eq(compiled_query.to_h)
  end

  it 'does not allow callers to replace the trusted compiler' do
    hostile_compiler = Object.new
    hostile_compiler.define_singleton_method(:compile) do |_plan|
      ZuQL::Contracts::CompiledQuery.from_h(
        backend: 'data_query', sql: 'DELETE FROM Account', warnings: []
      )
    end

    expect { described_class.new(compiler: hostile_compiler) }.to raise_error(ArgumentError)
  end

  it 'rejects a CompiledQuery subclass that forges serialized equality' do
    forged_class = Class.new(ZuQL::Contracts::CompiledQuery)
    trusted_hash = compiled_query.to_h
    forged = forged_class.new(
      backend: 'data_query', sql: 'DELETE FROM Account', warnings: []
    )
    forged.define_singleton_method(:to_h) { trusted_hash }

    expect { validator.validate!(plan, forged) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'invalid_input', input: 'compiled_query')
      end
  end

  it 'rejects a mutable CompiledQuery created through the direct constructor' do
    mutable = ZuQL::Contracts::CompiledQuery.new(
      backend: compiled_query.backend,
      sql: compiled_query.sql.dup,
      warnings: compiled_query.warnings.map(&:dup)
    )

    expect { validator.validate!(plan, mutable) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'invalid_input', input: 'compiled_query')
      end
  end

  it 'rejects an exact-class artifact with a singleton SQL accessor' do
    trusted_sql = compiled_query.sql
    forged = ZuQL::Contracts::CompiledQuery.new(
      backend: 'data_query', sql: trusted_sql, warnings: compiled_query.warnings
    )
    forged.warnings.each(&:freeze)
    forged.warnings.freeze
    forged.define_singleton_method(:sql) do
      validator_frame = caller_locations.any? { |frame| frame.path.end_with?('/sql_safety_validator.rb') }
      validator_frame ? trusted_sql : 'DELETE FROM Account'
    end
    forged.freeze

    expect { validator.validate!(plan, forged) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'invalid_input', input: 'compiled_query')
      end
  end

  it 'rejects frozen String subclasses in a compiled artifact' do
    deceptive_string_class = Class.new(String) do
      def to_str
        'DELETE FROM Account'
      end
    end
    deceptive_sql = deceptive_string_class.new(compiled_query.sql).freeze
    forged = ZuQL::Contracts::CompiledQuery.new(
      backend: 'data_query', sql: deceptive_sql, warnings: compiled_query.warnings
    )
    forged.warnings.each(&:freeze)
    forged.warnings.freeze
    forged.freeze

    expect { validator.validate!(plan, forged) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'invalid_input', input: 'compiled_query')
      end
  end

  it 'returns a deeply immutable compiled query' do
    validated = validator.validate!(plan, compiled_query)

    expect(validated).to be_frozen
    expect(validated.backend).to be_frozen
    expect(validated.sql).to be_frozen
    expect(validated.warnings).to be_frozen
    expect(validated.warnings).to all(be_frozen)
  end

  it 'accepts the configured maximum limit and rejects values above it' do
    maximum = replace_plan(plan, limit: 10_000)
    excessive = replace_plan(plan, limit: 10_001)

    expect(validator.validate!(maximum, compiler.compile(maximum))).to be_a(ZuQL::Contracts::CompiledQuery)
    expect { validator.validate!(excessive, compiled_query) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'limit_exceeded', limit: 10_001, max_limit: 10_000)
      end
  end

  it 'rejects a QueryPlan with a dynamic limit accessor' do
    forged_plan = ZuQL::Contracts::QueryPlan.new(plan.to_h)
    limit_calls = 0
    forged_plan.define_singleton_method(:limit) do
      limit_calls += 1
      limit_calls == 1 ? 1 : 10_001
    end
    forged_plan.freeze

    expect { validator.validate!(forged_plan, compiled_query) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'invalid_input', input: 'plan')
      end
  end

  it 'supports a smaller positive configured maximum' do
    strict_validator = described_class.new(max_limit: 50)

    expect { strict_validator.validate!(plan, compiled_query) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'limit_exceeded', max_limit: 50)
      end
  end

  it 'rejects invalid maximum-limit configuration' do
    expect { described_class.new(max_limit: 0) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'invalid_configuration')
      end
    expect { described_class.new(max_limit: '100') }.to raise_error(ZuQL::SafetyValidationError)
  end

  it 'rejects untyped plan and compiled-query inputs' do
    expect { validator.validate!({}, compiled_query) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'invalid_input', input: 'plan')
      end
    expect { validator.validate!(plan, {}) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'invalid_input', input: 'compiled_query')
      end
  end

  it 'rejects plans and compiled queries for another backend' do
    snowflake_plan = replace_plan(plan, backend: 'snowflake')
    snowflake_query = ZuQL::Contracts::CompiledQuery.from_h(
      backend: 'snowflake', sql: 'SELECT 1', warnings: []
    )

    expect { validator.validate!(snowflake_plan, snowflake_query) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'invalid_backend')
      end
    expect { validator.validate!(plan, snowflake_query) }.to raise_error(ZuQL::SafetyValidationError)
  end

  it 'wraps trusted compiler failures without exposing hostile SQL' do
    invalid_plan = replace_plan(
      plan, select: [{ field: 'subscription.made_up', alias: 'made_up' }]
    )

    expect { validator.validate!(invalid_plan, compiled_query) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'recompilation_failed')
        expect(error.message).not_to include(compiled_query.sql)
      end
  end

  it 'sanitizes unexpected trusted compiler failures' do
    trusted_query = compiled_query
    broken_compiler = instance_double(ZuQL::DataQueryCompiler)
    allow(ZuQL::DataQueryCompiler).to receive(:new).and_return(broken_compiler)
    allow(broken_compiler).to receive(:compile).and_raise(RuntimeError, 'SELECT hostile secret')

    expect { described_class.new.validate!(plan, trusted_query) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'recompilation_failed', compiler_error: 'RuntimeError')
        expect(error.message).not_to include('hostile secret')
        expect(error.details.to_s).not_to include('hostile secret')
      end
  end

  it 'sanitizes unexpected plan snapshot failures' do
    hostile_value = Object.new
    hostile_value.define_singleton_method(:to_json) do |*_options|
      raise 'SELECT hostile snapshot secret'
    end
    hostile_plan = replace_plan(
      plan,
      filters: [{ field: 'subscription.status', operator: '=', value: hostile_value }]
    )

    expect { validator.validate!(hostile_plan, compiled_query) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to include(reason: 'invalid_input', input: 'plan', error: 'RuntimeError')
        expect(error.message).not_to include('hostile snapshot secret')
        expect(error.details.to_s).not_to include('hostile snapshot secret')
      end
  end

  it 'deep-freezes structured safety error details' do
    forged = ZuQL::Contracts::CompiledQuery.from_h(
      backend: 'data_query', sql: 'SELECT 1', warnings: []
    )

    expect { validator.validate!(plan, forged) }
      .to raise_error(ZuQL::SafetyValidationError) do |error|
        expect(error.details).to be_frozen
        expect(error.details.fetch(:reason)).to be_frozen
      end
  end
end
