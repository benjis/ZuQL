# frozen_string_literal: true

module ZuQL
  # Compiles a backend-neutral QueryPlan into deterministic Data Query SQL.
  class DataQueryCompiler
    DEFAULT_MAX_LIMIT = 10_000

    def initialize(
      registry: DataQueryRegistry.new, literal: DataQueryLiteral.new,
      identifier: DataQueryIdentifier.new, max_limit: DEFAULT_MAX_LIMIT
    )
      validate_max_limit!(max_limit)

      @registry = registry
      @literal = literal
      @identifier = identifier
      @max_limit = max_limit
    end

    def compile(plan)
      validate_plan!(plan)
      DataQueryCompilation.new(plan, @registry, @literal, @identifier, @max_limit).compile
    end

    private

    def validate_max_limit!(max_limit)
      return if max_limit.is_a?(Integer) && max_limit.positive?

      raise CompilationError.new(
        'Data Query compiler maximum limit must be a positive integer',
        details: { kind: 'limit', value: max_limit }
      )
    end

    def validate_plan!(plan)
      unless plan.instance_of?(Contracts::QueryPlan) && plan.frozen? && plan.singleton_methods(false).empty?
        raise CompilationError.new('Data Query compiler requires a QueryPlan', details: { actual: plan.class.name })
      end
      return if plan.backend == 'data_query'

      raise CompilationError.new(
        'Data Query compiler cannot compile another backend', details: { backend: plan.backend }
      )
    end
  end

  # Holds per-compilation join state, mappings, warnings, and clause rendering.
  class DataQueryCompilation # rubocop:disable Metrics/ClassLength
    def initialize(plan, registry, literal, identifier, max_limit)
      @plan = plan
      @registry = registry
      @literal = literal
      @identifier = identifier
      @max_limit = max_limit
      @filter_validator = DataQueryFilterValidator.new(registry)
      @joined = { plan.root_object => true }
      @warnings = plan.warnings.dup
    end

    def compile
      validate_limit!
      DataQuerySelectionValidator.new.validate!(@plan)
      from = from_clause
      joins = join_clauses
      sql = [select_clause, from, *joins, where_clause, group_clause, order_clause, limit_clause].compact.join("\n")
      Contracts::CompiledQuery.from_h(backend: 'data_query', sql: sql, warnings: @warnings)
    end

    private

    def select_clause
      invalid('selection', 'at least one selection is required') if @plan.select.empty?
      rendered = @plan.select.map { |selection| "  #{selection_sql(selection)}" }.join(",\n")
      "SELECT\n#{rendered}"
    end

    def selection_sql(selection)
      has_field = !selection.field.nil?
      has_metric = !selection.metric.nil?
      invalid('selection', 'exactly one field or metric is required') if has_field == has_metric

      expression = selection_expression(selection)
      "#{expression} AS #{@identifier.render(selection.alias)}"
    end

    def selection_expression(selection)
      return metric_sql(selection.metric) if selection.field.nil?

      invalid('selection field', selection.field) unless @registry.field(selection.field).fetch(:selectable)
      field_sql(selection.field)
    end

    def metric_sql(metric_id)
      metric = @registry.metric(metric_id)
      invalid('metric grain', metric_id) unless metric.fetch(:native_grain).is_a?(String)
      field = field_sql(metric.fetch(:field))
      case metric.fetch(:aggregation)
      when 'sum' then "SUM(#{field})"
      when 'count_distinct' then "COUNT(DISTINCT #{field})"
      else invalid('aggregation', metric.fetch(:aggregation))
      end
    end

    def from_clause
      object = object_metadata(@plan.root_object)
      "FROM #{@identifier.render(object.fetch(:physical_name))} AS #{@identifier.render(@plan.root_object)}"
    end

    def join_clauses
      @plan.joins.map { |join| render_join(join) }
    end

    def render_join(join)
      relationship = @registry.relationship(join.relationship)
      invalid('join type', join.join_type) unless %w[inner left].include?(join.join_type)
      new_object = new_joined_object(relationship, join.relationship)
      object = object_metadata(new_object)
      @joined[new_object] = true
      "#{join.join_type.upcase} JOIN #{@identifier.render(object.fetch(:physical_name))} " \
        "AS #{@identifier.render(new_object)} " \
        "ON #{join_condition(relationship)}"
    end

    def new_joined_object(relationship, relationship_id)
      from_joined = @joined.key?(relationship.fetch(:from_object))
      to_joined = @joined.key?(relationship.fetch(:to_object))
      invalid('join', relationship_id) if from_joined == to_joined

      from_joined ? relationship.fetch(:to_object) : relationship.fetch(:from_object)
    end

    def join_condition(relationship)
      from_field = "#{relationship.fetch(:from_object)}.#{relationship.fetch(:from_field)}"
      to_field = "#{relationship.fetch(:to_object)}.#{relationship.fetch(:to_field)}"
      "#{field_sql(from_field)} = #{field_sql(to_field)}"
    end

    def where_clause
      return if @plan.filters.empty?

      rendered = @plan.filters.map do |filter|
        @filter_validator.validate!(filter)
        @literal.filter(field_sql(filter.field), filter.operator, filter.value)
      end
      "WHERE #{rendered.join("\n  AND ")}"
    end

    def group_clause
      return if @plan.group_by.empty?

      "GROUP BY #{@plan.group_by.map { |field| field_sql(field) }.join(', ')}"
    end

    def order_clause
      DataQueryOrder.new(@identifier).render(@plan.order_by, @plan.select.map(&:alias))
    end

    def limit_clause
      "LIMIT #{@plan.limit}"
    end

    def field_sql(qualified_id)
      field = @registry.field(qualified_id)
      invalid('field object not joined', qualified_id) unless @joined.key?(field.fetch(:object_id))

      "#{@identifier.render(field.fetch(:object_id))}.#{@identifier.render(field.fetch(:physical_name))}"
    end

    def validate_limit!
      invalid('limit', @plan.limit) unless @plan.limit.is_a?(Integer) && @plan.limit.between?(1, @max_limit)
    end

    def object_metadata(id)
      object = @registry.object(id)
      @warnings.concat(object.fetch(:warnings)).uniq!
      object
    end

    def invalid(kind, value)
      raise CompilationError.new(
        "Invalid Data Query #{kind}: #{value}", details: { kind: kind, value: value }
      )
    end
  end
end
