# frozen_string_literal: true

module ZuQL
  # Validates metric grain compatibility and aggregate fan-out safety.
  class GrainValidator
    def initialize(query_spec, resolutions, registry)
      @query_spec = query_spec
      @metrics = resolutions.filter_map do |resolution|
        registry.metric(resolution.resolved_to) if resolution.kind == 'metric'
      end
    end

    def validate_grains!
      grains = @metrics.to_h { |metric| [metric.fetch(:id), metric.fetch(:native_grain)] }
      raise IncompatibleMetricGrainsError, grains if grains.values.uniq.length > 1
    end

    def validate_shape!
      if @query_spec.intent == 'detail_export'
        raise InvalidQueryShapeError.new(@query_spec.intent, 'metrics_not_allowed') unless @metrics.empty?

        return
      end

      raise InvalidQueryShapeError.new(@query_spec.intent, 'metric_required') if @metrics.empty?
      return if @query_spec.requested_fields.empty?

      raise InvalidQueryShapeError.new(@query_spec.intent, 'requested_fields_not_grouped')
    end

    def validate_fanout!(paths)
      return if @query_spec.intent == 'detail_export'

      @metrics.reject { |metric| metric.fetch(:aggregation) == 'count_distinct' }
              .each { |metric| validate_metric!(metric, paths) }
    end

    private

    def validate_metric!(metric, paths)
      risky_edge = paths.find { |edge| duplicates_grain?(edge) }
      return unless risky_edge

      raise FanoutRiskError.new(
        metric: metric.fetch(:id), native_grain: metric.fetch(:native_grain),
        edge: risky_edge, path: affected_path(metric.fetch(:native_grain), risky_edge, paths)
      )
    end

    def affected_path(root, risky_edge, paths)
      paths_by_object = { root => [] }
      paths.each do |edge|
        prefix = paths_by_object.fetch(edge.fetch(:traverse_from), [])
        current_path = prefix + [edge.fetch(:id)]
        return current_path if edge.equal?(risky_edge)

        paths_by_object[edge.fetch(:traverse_to)] = current_path
      end
    end

    def duplicates_grain?(edge)
      forward = edge.fetch(:traverse_from) == edge.fetch(:from_object)
      case edge.fetch(:cardinality)
      when 'one_to_many' then forward
      when 'many_to_one' then !forward
      when 'many_to_many' then true
      else false
      end
    end
  end
end
