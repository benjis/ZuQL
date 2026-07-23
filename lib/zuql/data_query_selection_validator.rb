# frozen_string_literal: true

module ZuQL
  # Validates cross-selection alias and aggregate grouping invariants.
  class DataQuerySelectionValidator
    def validate!(plan)
      invalid('selection', 'at least one selection is required') if plan.select.empty?
      validate_aliases!(plan.select)
      validate_selection_shapes!(plan.select)
      validate_grouping!(plan)
    end

    private

    def validate_aliases!(selections)
      aliases = selections.map(&:alias)
      return if aliases.uniq.length == aliases.length

      invalid('selection alias', 'aliases must be unique')
    end

    def validate_selection_shapes!(selections)
      selections.each do |selection|
        has_field = !selection.field.nil?
        has_metric = !selection.metric.nil?
        invalid('selection', 'exactly one field or metric is required') if has_field == has_metric
      end
    end

    def validate_grouping!(plan)
      fields = plan.select.filter_map(&:field)
      metrics = plan.select.filter_map(&:metric)
      validate_grouping_shape!(plan.group_by, metrics)
      return if metrics.empty?

      validate_grouping_fields!(plan.group_by, fields)
    end

    def validate_grouping_shape!(group_by, metrics)
      invalid('grouping', 'duplicate fields') unless group_by.uniq == group_by
      invalid('grouping', 'GROUP BY requires a metric') if metrics.empty? && !group_by.empty?
    end

    def validate_grouping_fields!(group_by, fields)
      missing = fields - group_by
      invalid('grouping', "missing fields: #{missing.join(', ')}") unless missing.empty?
      extra = group_by - fields
      invalid('grouping', "unselected fields: #{extra.join(', ')}") unless extra.empty?
    end

    def invalid(kind, value)
      raise CompilationError.new(
        "Invalid Data Query #{kind}: #{value}", details: { kind: kind, value: value }
      )
    end
  end
end
