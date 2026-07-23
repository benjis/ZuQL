# frozen_string_literal: true

module ZuQL
  # Enforces registry field capabilities and known scalar types at compile time.
  class DataQueryFilterValidator
    def initialize(registry)
      @registry = registry
    end

    def validate!(filter)
      metadata = @registry.field(filter.field)
      invalid('filter field', filter.field) unless metadata.fetch(:filterable)
      values = filter.value.is_a?(Array) ? filter.value : [filter.value]
      return if values.all? { |value| compatible_value?(metadata.fetch(:type), value) }

      invalid('filter value type', "#{filter.field}:#{metadata.fetch(:type)}")
    end

    private

    def compatible_value?(type, value) # rubocop:disable Metrics/CyclomaticComplexity
      return true if value.nil? || type == 'unknown'

      case type
      when 'integer' then value.is_a?(Integer)
      when 'decimal' then value.is_a?(Numeric) && value.finite?
      when 'boolean' then [true, false].include?(value)
      when 'date' then value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      when 'datetime' then value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T[^\s]+\z/)
      when 'string', 'fixed' then value.is_a?(String)
      else false
      end
    end

    def invalid(kind, value)
      raise CompilationError.new(
        "Invalid Data Query #{kind}: #{value}", details: { kind: kind, value: value }
      )
    end
  end
end
