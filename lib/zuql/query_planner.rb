# frozen_string_literal: true

module ZuQL
  # Orchestrates deterministic planning from a resolved semantic request.
  class QueryPlanner
    def initialize(registry: SemanticRegistry.new, graph: RelationshipGraph.new)
      @registry = registry
      @graph = graph
    end

    def plan(resolved_query)
      validate_contract!(resolved_query)
      root, paths = root_and_paths(resolved_query)
      Contracts::QueryPlan.from_h(plan_attributes(resolved_query, root, paths))
    end

    private

    def validate_contract!(resolved_query)
      return if resolved_query.is_a?(Contracts::ResolvedQuery)

      raise ContractError.new('QueryPlanner requires a ResolvedQuery', details: { actual: resolved_query.class.name })
    end

    def root_and_paths(resolved_query)
      validator = GrainValidator.new(resolved_query.query_spec, resolved_query.resolutions, @registry)
      validator.validate_shape!
      validator.validate_grains!
      root = root_object(resolved_query.query_spec, resolved_query.resolutions)
      raise MissingRootObjectError, resolved_query.query_spec.intent unless root

      paths = planned_paths(root, required_objects(resolved_query.resolutions))
      validator.validate_fanout!(paths)
      [root, paths]
    end

    def plan_attributes(resolved_query, root, paths)
      spec = resolved_query.query_spec
      projection = PlanProjection.new(spec, resolved_query.resolutions, @registry)
      {
        backend: backend(spec.backend_preference), root_object: root,
        select: projection.selections, joins: joins(paths), filters: projection.filters,
        group_by: projection.grouping, order_by: spec.order_by, limit: spec.limit,
        grain: grain(spec, resolved_query.resolutions, root), warnings: resolved_query.warnings
      }
    end

    def root_object(query_spec, resolutions)
      return detail_root(query_spec, resolutions) if query_spec.intent == 'detail_export'

      metric_root(resolutions) || entity_root(query_spec, resolutions) ||
        field_root(query_spec, resolutions) || semantic_root(query_spec, resolutions)
    end

    def detail_root(query_spec, resolutions)
      entity_root(query_spec, resolutions) || field_root(query_spec, resolutions) ||
        semantic_root(query_spec, resolutions) || metric_root(resolutions)
    end

    def metric_root(resolutions)
      metric = resolutions.find { |resolution| resolution.kind == 'metric' }
      @registry.metric(metric.resolved_to).fetch(:native_grain) if metric
    end

    def entity_root(query_spec, resolutions)
      concept = query_spec.requested_entities.first
      resolution_for(resolutions, concept, 'object')&.resolved_to
    end

    def field_root(query_spec, resolutions)
      concept = query_spec.requested_fields.first&.concept
      resolution = resolution_for(resolutions, concept, 'field')
      object_for(resolution) if resolution
    end

    def semantic_root(query_spec, resolutions)
      concept = (query_spec.dimensions + query_spec.group_by).first || query_spec.filters.first&.concept
      resolution = resolution_for(resolutions, concept)
      object_for(resolution) if resolution
    end

    def planned_paths(root, targets)
      @graph.paths(root, targets)
    rescue UnreachableObjectsError
      raise JoinPathError.new(root, targets)
    end

    def required_objects(resolutions)
      resolutions.map { |resolution| object_for(resolution) }.uniq
    end

    def object_for(resolution)
      return resolution.resolved_to if resolution.kind == 'object'
      return resolution.resolved_to.split('.', 2).first if resolution.kind == 'field'

      @registry.public_send(resolution.kind, resolution.resolved_to).fetch(:field).split('.', 2).first
    end

    def grain(query_spec, resolutions, root)
      return @registry.object(root).fetch(:default_grain) if query_spec.intent == 'detail_export'

      metric_root(resolutions) || @registry.object(root).fetch(:default_grain)
    end

    def joins(paths)
      paths.map { |edge| { relationship: edge.fetch(:id), join_type: 'inner' } }
    end

    def resolution_for(resolutions, concept, kind = nil)
      normalized = normalize(concept)
      resolutions.find do |resolution|
        normalize(resolution.input) == normalized && (kind.nil? || resolution.kind == kind)
      end
    end

    def backend(preference)
      preference == 'auto' ? 'data_query' : preference
    end

    def normalize(value)
      value.to_s.strip.downcase.gsub(/\s+/, ' ')
    end
  end
end
