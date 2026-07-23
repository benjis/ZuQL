# frozen_string_literal: true

module ZuQL
  # Rejects filter shapes, operators, and values incompatible with known field types.
  class FilterCompatibilityValidator
    SET_OPERATORS = %w[in not_in].freeze
    ORDERED_OPERATORS = %w[gt gte lt lte].freeze
    ORDERED_TYPES = %w[integer decimal date datetime].freeze

    def initialize(registry)
      @registry = registry
    end

    def validate!(field, filter)
      type = @registry.field(field).fetch(:type, 'unknown').to_s.downcase
      reason = shape_error(filter.operator, filter.value) ||
               operator_error(type, filter.operator) || value_error(type, filter.value)
      return unless reason

      raise IncompatibleFilterError.new(
        field: field, field_type: type, operator: filter.operator,
        value: filter.value, reason: reason
      )
    end

    private

    def shape_error(operator, value)
      return 'array_required' if SET_OPERATORS.include?(operator) && (!value.is_a?(Array) || value.empty?)

      'scalar_required' if !SET_OPERATORS.include?(operator) && value.is_a?(Array)
    end

    def operator_error(type, operator)
      return 'contains_requires_string_field' if operator == 'contains' && !%w[string unknown].include?(type)
      return unless ORDERED_OPERATORS.include?(operator) && type != 'unknown' && !ORDERED_TYPES.include?(type)

      'ordered_comparison_requires_ordered_field'
    end

    def value_error(type, value)
      values = value.is_a?(Array) ? value : [value]
      'value_type_mismatch' unless values.all? { |item| compatible_value?(type, item) }
    end

    def compatible_value?(type, value)
      case type
      when 'integer' then value.is_a?(Integer)
      when 'decimal' then value.is_a?(Numeric)
      when 'date', 'datetime', 'string', 'fixed' then value.is_a?(String)
      else true
      end
    end
  end
end
