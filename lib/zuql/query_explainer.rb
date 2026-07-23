# frozen_string_literal: true

module ZuQL
  # Converts typed query artifacts into a deterministic, human-readable explanation.
  class QueryExplainer # rubocop:disable Metrics/ClassLength
    PUBLIC_MODEL_LIMITATION =
      'ZuQL uses a public canonical model; tenant-specific fields, features, and mappings may differ.'
    REAL_ATTRIBUTES = Contracts::Base.instance_method(:attributes)
    REAL_CLASS = Kernel.instance_method(:class)
    REAL_INSTANCE_OF = Kernel.instance_method(:instance_of?)
    REAL_SINGLETON_METHODS = Kernel.instance_method(:singleton_methods)
    CONTRACT_CLASSES = [
      Contracts::QuerySpec, Contracts::RequestedField, Contracts::ConceptFilter,
      Contracts::ResolvedQuery, Contracts::Resolution, Contracts::QueryPlan,
      Contracts::Selection, Contracts::Join, Contracts::PlanFilter, Contracts::CompiledQuery
    ].freeze
    SCALAR_CLASSES = [NilClass, TrueClass, FalseClass, Integer, Float, Symbol].freeze

    def explain(query_spec:, resolved_query:, plan:, compiled_query:)
      validate!(query_spec, Contracts::QuerySpec, 'query_spec')
      validate!(resolved_query, Contracts::ResolvedQuery, 'resolved_query')
      validate!(plan, Contracts::QueryPlan, 'plan')
      validate!(compiled_query, Contracts::CompiledQuery, 'compiled_query')

      Contracts::QueryExplanation.from_h(explanation_attributes(query_spec, resolved_query, plan, compiled_query))
    end

    private

    def explanation_attributes( # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      query_spec, resolved_query, plan, compiled_query
    )
      {
        summary: "Intent #{query_spec.intent} on #{plan.backend}, rooted at #{plan.root_object}, limit #{plan.limit}.",
        interpretation: interpretation_sentence(query_spec),
        resolutions: resolved_query.resolutions.map { |resolution| resolution_sentence(resolution) },
        filters: filter_sentences(plan), metrics: metric_sentences(plan),
        root: "Planner selected #{plan.root_object} as the root object.",
        joins: join_sentences(plan), inserted_bridges: inserted_bridges(plan, resolved_query),
        grain: "Result grain: #{plan.grain}.",
        grouping: grouping_sentence(plan), backend: "Backend: #{compiled_query.backend}.",
        assumptions: assumptions, mapping_status: mapping_status(compiled_query),
        limitation: PUBLIC_MODEL_LIMITATION, sql: compiled_query.sql
      }
    end

    def validate!(value, expected, name)
      exact = REAL_INSTANCE_OF.bind_call(value, expected)
      return if exact && trusted_tree?(value)

      raise ContractError.new("QueryExplainer requires an exact #{expected.name}", details: { input: name })
    end

    def trusted_tree?(value)
      return false unless REAL_SINGLETON_METHODS.bind_call(value).empty?

      trusted_value?(value)
    end

    def trusted_value?(value)
      case value
      when Contracts::Base then trusted_contract?(value)
      when Hash then trusted_hash?(value)
      when Array then trusted_array?(value)
      when String then exact?(value, String)
      else SCALAR_CLASSES.include?(REAL_CLASS.bind_call(value))
      end
    end

    def trusted_hash?(value)
      exact?(value, Hash) && value.all? { |key, item| trusted_tree?(key) && trusted_tree?(item) }
    end

    def trusted_array?(value)
      exact?(value, Array) && value.all? { |item| trusted_tree?(item) }
    end

    def trusted_contract?(value)
      CONTRACT_CLASSES.include?(REAL_CLASS.bind_call(value)) && trusted_tree?(REAL_ATTRIBUTES.bind_call(value))
    end

    def exact?(value, klass)
      REAL_INSTANCE_OF.bind_call(value, klass)
    end

    def resolution_sentence(resolution)
      "#{resolution.input} → #{resolution.resolved_to} " \
        "(#{resolution.kind}, confidence #{resolution.confidence})."
    end

    def interpretation_sentence(spec)
      "Interpreted as #{spec.intent}; entities: #{list_or_none(spec.requested_entities)}; " \
        "fields: #{list_or_none(spec.requested_fields.map(&:concept))}."
    end

    def filter_sentences(plan)
      return ['No filters.'] if plan.filters.empty?

      plan.filters.map { |filter| "#{filter.field} #{filter.operator} #{filter.value.inspect}." }
    end

    def metric_sentences(plan)
      metrics = plan.select.filter_map(&:metric)
      metrics.empty? ? ['No metrics.'] : metrics.map { |metric| "Metric: #{metric}." }
    end

    def inserted_bridges(plan, resolved_query)
      requested = resolved_query.resolutions.filter_map { |resolution| resolution_object_id(resolution) }
      candidates = plan.joins.flat_map { |join| join.relationship.split('.') }.uniq
      bridges = candidates - requested - [plan.root_object]
      bridges.empty? ? ['No bridge objects inserted.'] : bridges.map { |object| "Inserted bridge: #{object}." }
    end

    def resolution_object_id(resolution)
      return resolution.resolved_to if resolution.kind == 'object'
      return resolution.resolved_to.split('.', 2).first if resolution.kind == 'field'

      nil
    end

    def assumptions
      ['Natural-language interpretation is constrained to the supported MVP domain.',
       'Generated SQL is a preview and is not executed by ZuQL.']
    end

    def mapping_status(compiled_query)
      unverified = compiled_query.warnings.grep(/convention-derived|unverified/i)
      return 'Mapping status: all used object mappings are user-observed and verified.' if unverified.empty?

      "Mapping status: #{unverified.length} used object mapping(s) are convention-derived and unverified."
    end

    def list_or_none(values)
      values.empty? ? 'none' : values.join(', ')
    end

    def join_sentences(plan)
      return ['No joins required.'] if plan.joins.empty?

      plan.joins.map { |join| "#{join.join_type.upcase} JOIN via #{join.relationship}." }
    end

    def grouping_sentence(plan)
      return 'No grouping.' if plan.group_by.empty?

      "Grouped by: #{plan.group_by.join(', ')}."
    end
  end
end
