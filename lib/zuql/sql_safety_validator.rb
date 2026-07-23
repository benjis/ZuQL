# frozen_string_literal: true

module ZuQL
  # Verifies that SQL is the exact immutable output of the trusted compiler.
  class SqlSafetyValidator
    DEFAULT_MAX_LIMIT = 10_000

    def initialize(max_limit: DEFAULT_MAX_LIMIT)
      unless max_limit.is_a?(Integer) && max_limit.positive?
        raise SafetyValidationError.new(
          'Maximum limit must be a positive integer',
          details: { reason: 'invalid_configuration', max_limit: max_limit }
        )
      end

      @compiler = DataQueryCompiler.new
      @max_limit = max_limit
    end

    def validate!(plan, compiled_query)
      trusted_plan = validate_inputs!(plan, compiled_query)
      validate_backends!(trusted_plan, compiled_query)
      validate_limit!(trusted_plan)
      expected = recompile(trusted_plan)
      fail!('compiled_query_mismatch', 'Compiled query does not match trusted output') \
        unless artifacts_match?(expected, compiled_query)

      expected
    end

    private

    def validate_inputs!(plan, compiled_query)
      unless valid_query_plan_object?(plan)
        fail!('invalid_input', 'Safety validator requires a QueryPlan', input: 'plan')
      end
      unless immutable_compiled_query?(compiled_query)
        fail!('invalid_input', 'Safety validator requires an immutable CompiledQuery', input: 'compiled_query')
      end

      snapshot_plan(plan)
    end

    def validate_backends!(plan, compiled_query)
      return if plan.backend == 'data_query' && compiled_query.backend == 'data_query'

      fail!(
        'invalid_backend', 'Safety validator supports Data Query only',
        plan_backend: plan.backend, compiled_backend: compiled_query.backend
      )
    end

    def validate_limit!(plan)
      return if plan.limit <= @max_limit

      fail!(
        'limit_exceeded', 'Query limit exceeds the configured maximum',
        limit: plan.limit, max_limit: @max_limit
      )
    end

    def recompile(plan)
      @compiler.compile(plan)
    rescue StandardError => e
      fail!(
        'recompilation_failed', 'Trusted compiler rejected the query plan',
        compiler_error: e.class.name
      )
    end

    def immutable_compiled_query?(compiled_query)
      valid_compiled_query_object?(compiled_query) && valid_compiled_query_attributes?(compiled_query)
    end

    def valid_query_plan_object?(plan)
      plan.instance_of?(Contracts::QueryPlan) &&
        plan.frozen? && singleton_methods_for(plan).empty?
    end

    def snapshot_plan(plan)
      attributes = Contracts::Base.instance_method(:to_h).bind_call(plan)
      snapshot = JSON.parse(JSON.generate(attributes))
      Contracts::QueryPlan.from_h(snapshot)
    rescue StandardError => e
      fail!('invalid_input', 'Safety validator could not snapshot QueryPlan', input: 'plan', error: e.class.name)
    end

    def valid_compiled_query_object?(compiled_query)
      compiled_query.instance_of?(Contracts::CompiledQuery) &&
        compiled_query.frozen? && singleton_methods_for(compiled_query).empty?
    end

    def valid_compiled_query_attributes?(compiled_query)
      backend = compiled_attribute(compiled_query, :backend)
      sql = compiled_attribute(compiled_query, :sql)
      warnings = compiled_attribute(compiled_query, :warnings)
      plain_frozen_string?(backend) && plain_frozen_string?(sql) &&
        plain_frozen_warnings?(warnings)
    end

    def plain_frozen_warnings?(warnings)
      warnings.instance_of?(Array) && warnings.frozen? &&
        warnings.all? { |warning| plain_frozen_string?(warning) }
    end

    def artifacts_match?(expected, actual)
      expected.backend == compiled_attribute(actual, :backend) &&
        expected.sql == compiled_attribute(actual, :sql) &&
        expected.warnings == compiled_attribute(actual, :warnings)
    end

    def compiled_attribute(compiled_query, name)
      Contracts::CompiledQuery.instance_method(name).bind_call(compiled_query)
    end

    def singleton_methods_for(value)
      Object.instance_method(:singleton_methods).bind_call(value, false)
    end

    def plain_frozen_string?(value)
      value.instance_of?(String) && value.frozen?
    end

    def fail!(reason, message, details = {})
      raise SafetyValidationError.new(message, details: details.merge(reason: reason))
    end
  end
end
