# frozen_string_literal: true

module ZuQL
  # Safely renders typed QueryPlan filter values for Data Query SQL.
  class DataQueryLiteral
    SCALAR_OPERATORS = %w[= != > >= < <=].freeze
    SET_OPERATORS = ['IN', 'NOT IN'].freeze

    def filter(column_sql, operator, value)
      return null_filter(column_sql, operator) if value.nil?
      return set_filter(column_sql, operator, value) if SET_OPERATORS.include?(operator)
      return like_filter(column_sql, value) if operator == 'LIKE'

      invalid(operator, value, 'unsupported operator') unless SCALAR_OPERATORS.include?(operator)
      "#{column_sql} #{operator} #{scalar(value, operator)}"
    end

    private

    def null_filter(column_sql, operator)
      return "#{column_sql} IS NULL" if operator == '='
      return "#{column_sql} IS NOT NULL" if operator == '!='

      invalid(operator, nil, 'NULL requires = or !=')
    end

    def set_filter(column_sql, operator, value)
      invalid(operator, value, 'set operator requires a non-empty array') unless value.is_a?(Array) && !value.empty?
      invalid(operator, value, 'set members cannot be NULL') if value.any?(&:nil?)

      rendered = value.map { |item| scalar(item, operator) }.join(', ')
      "#{column_sql} #{operator} (#{rendered})"
    end

    def like_filter(column_sql, value)
      invalid('LIKE', value, 'LIKE requires a string') unless value.is_a?(String)

      escaped = value.gsub(/([\\%_])/) { |character| "\\#{character}" }
      "#{column_sql} LIKE #{quote("%#{escaped}%")} ESCAPE '\\'"
    end

    def scalar(value, operator)
      case value
      when String then quote(value)
      when Integer then value.to_s
      when Float then finite_float(value, operator)
      when TrueClass then 'TRUE'
      when FalseClass then 'FALSE'
      else invalid(operator, value, 'unsupported value type')
      end
    end

    def finite_float(value, operator)
      invalid(operator, value, 'float must be finite') unless value.finite?

      value.to_s
    end

    def quote(value)
      "'#{value.gsub("'", "''")}'"
    end

    def invalid(operator, value, reason)
      raise CompilationError.new(
        "Invalid Data Query filter: #{reason}",
        details: { operator: operator, value_class: value.class.name, reason: reason }
      )
    end
  end
end
