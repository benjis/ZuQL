# frozen_string_literal: true

module ZuQL
  # Resolves the typed concepts in QuerySpec without guessing or planning SQL.
  class SemanticResolver
    def initialize(registry: SemanticRegistry.new, graph: RelationshipGraph.new)
      @registry = registry
      @graph = graph
    end

    def resolve(query_spec)
      unless query_spec.is_a?(Contracts::QuerySpec)
        raise ContractError.new('SemanticResolver requires a QuerySpec', details: { actual: query_spec.class.name })
      end

      matches = resolve_all(query_spec)
      @graph.connect!(matches.map { |entry| entry.fetch(:match).fetch(:object_id) }.uniq)

      Contracts::ResolvedQuery.from_h(
        query_spec: query_spec,
        resolutions: resolutions(matches),
        warnings: stable_warnings(matches)
      )
    end

    private

    def resolve_all(query_spec)
      entries = concept_groups(query_spec).flat_map { |concepts, kind| resolve_concepts(concepts, kind) }
      entries.concat(query_spec.filters.map { |filter| resolve_filter(filter.concept) })
      unique_entries(entries)
    end

    def concept_groups(query_spec)
      [
        [query_spec.metrics, :metric], [query_spec.dimensions, :dimension],
        [query_spec.group_by, :dimension], [query_spec.requested_entities, :object],
        [query_spec.requested_fields.map(&:concept), :field]
      ]
    end

    def resolve_concepts(concepts, kind)
      concepts.map { |concept| resolved_entry(concept, kind) }
    end

    def resolve_filter(concept)
      resolved_entry(concept, :dimension)
    rescue UnknownConceptError
      resolved_entry(concept, :field)
    end

    def resolved_entry(concept, kind)
      { input: concept, match: @registry.resolve(concept, kind) }
    end

    def unique_entries(entries)
      entries.each_with_object([]) do |entry, unique|
        match = entry.fetch(:match)
        key = [normalize(entry.fetch(:input)), match.fetch(:id), match.fetch(:kind)]
        unique << entry unless unique.any? { |existing| entry_key(existing) == key }
      end
    end

    def entry_key(entry)
      match = entry.fetch(:match)
      [normalize(entry.fetch(:input)), match.fetch(:id), match.fetch(:kind)]
    end

    def resolutions(entries)
      entries.map do |entry|
        match = entry.fetch(:match)
        {
          input: entry.fetch(:input), resolved_to: match.fetch(:id), kind: match.fetch(:kind),
          confidence: match.fetch(:confidence), alternatives: []
        }
      end
    end

    def stable_warnings(entries)
      entries.flat_map { |entry| entry.fetch(:match).fetch(:warnings) }.uniq
    end

    def normalize(value)
      value.strip.downcase.gsub(/\s+/, ' ')
    end
  end
end
