# frozen_string_literal: true

module ZuQL
  # Projects resolved concepts into selections, filters, and grouping.
  class PlanProjection
    OPERATORS = {
      'equals' => '=', 'not_equals' => '!=', 'in' => 'IN', 'not_in' => 'NOT IN',
      'gt' => '>', 'gte' => '>=', 'lt' => '<', 'lte' => '<=', 'contains' => 'LIKE'
    }.freeze

    def initialize(query_spec, resolutions, registry)
      @query_spec = query_spec
      @resolutions = resolutions
      @registry = registry
      @filter_validator = FilterCompatibilityValidator.new(registry)
    end

    def selections
      unique(field_selections + dimension_selections + metric_selections)
    end

    def filters
      @query_spec.filters.map { |filter| project_filter(filter) }
    end

    def grouping
      return [] if @query_spec.intent == 'detail_export'

      dimension_concepts.map { |concept| dimension_field(concept) }.uniq
    end

    private

    def field_selections
      @query_spec.requested_fields.map do |requested|
        field = resolution_for(requested.concept, 'field').resolved_to
        { field: field, alias: field.tr('.', '_') }
      end
    end

    def dimension_selections
      dimension_concepts.map do |concept|
        resolution = resolution_for(concept, 'dimension')
        { field: dimension_field(concept), alias: resolution.resolved_to }
      end
    end

    def metric_selections
      @query_spec.metrics.map do |concept|
        id = resolution_for(concept, 'metric').resolved_to
        { metric: id, alias: id }
      end
    end

    def unique(candidates)
      deduplicated = candidates.each_with_object([]) do |selection, result|
        key = selection[:field] || selection[:metric]
        result << selection unless result.any? { |item| (item[:field] || item[:metric]) == key }
      end
      unique_aliases(deduplicated)
    end

    def unique_aliases(selections)
      counts = Hash.new(0)
      selections.map do |selection|
        alias_name = selection.fetch(:alias)
        counts[alias_name] += 1
        suffix = counts.fetch(alias_name) == 1 ? '' : "_#{counts.fetch(alias_name)}"
        selection.merge(alias: "#{alias_name}#{suffix}")
      end
    end

    def project_filter(filter)
      resolution = resolution_for(filter.concept)
      field = resolution.kind == 'dimension' ? dimension_field(filter.concept) : resolution.resolved_to
      @filter_validator.validate!(field, filter)
      { field: field, operator: OPERATORS.fetch(filter.operator), value: filter.value }
    end

    def dimension_field(concept)
      id = resolution_for(concept, 'dimension').resolved_to
      @registry.dimension(id).fetch(:field)
    end

    def dimension_concepts
      @query_spec.dimensions + @query_spec.group_by
    end

    def resolution_for(concept, kind = nil)
      normalized = normalize(concept)
      @resolutions.find do |resolution|
        normalize(resolution.input) == normalized && (kind.nil? || resolution.kind == kind)
      end
    end

    def normalize(value)
      value.to_s.strip.downcase.gsub(/\s+/, ' ')
    end
  end
end
