# frozen_string_literal: true

module ZuQL
  # Renders ORDER BY using selected aliases only.
  class DataQueryOrder
    def initialize(identifier = DataQueryIdentifier.new)
      @identifier = identifier
    end

    def render(order_by, aliases)
      return if order_by.empty?

      rendered = order_by.map { |order| render_entry(order, aliases) }
      "ORDER BY #{rendered.join(', ')}"
    end

    private

    def render_entry(order, aliases)
      invalid(order) unless order.is_a?(Hash) && order.keys.sort == %i[direction field]
      field = order.fetch(:field)
      direction = order.fetch(:direction)
      invalid(field) unless aliases.include?(field)
      invalid(direction) unless %w[asc desc].include?(direction)

      "#{@identifier.render(field)} #{direction.upcase}"
    end

    def invalid(value)
      raise CompilationError.new(
        "Invalid Data Query order: #{value}", details: { kind: 'order_by', value: value }
      )
    end
  end
end
