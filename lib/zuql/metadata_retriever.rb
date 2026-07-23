# frozen_string_literal: true

require 'yaml'

module ZuQL
  # Selects a small, deterministic slice of public canonical metadata for a question.
  class MetadataRetriever
    DEFAULT_PATHS = SemanticRegistry::DEFAULT_PATHS.merge(
      relationships: File.expand_path('../../data/canonical/relationships.yml', __dir__)
    ).freeze
    LIMITS = { objects: 8, fields: 24, metrics: 8, dimensions: 8, relationships: 12 }.freeze

    def initialize(paths: DEFAULT_PATHS, limits: LIMITS)
      @limits = LIMITS.merge(limits).freeze
      @objects = YAML.safe_load_file(paths.fetch(:objects)).fetch('objects')
      @metrics = YAML.safe_load_file(paths.fetch(:metrics)).fetch('metrics')
      @dimensions = YAML.safe_load_file(paths.fetch(:dimensions)).fetch('dimensions')
      @relationships = YAML.safe_load_file(paths.fetch(:relationships)).fetch('relationships')
    end

    def retrieve(question) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      terms = tokens(question)
      metrics = ranked(@metrics, terms, @limits.fetch(:metrics))
      dimensions = ranked(@dimensions, terms, @limits.fetch(:dimensions))
      fields = ranked_fields(terms)
      object_ids = relevant_object_ids(terms, metrics, dimensions, fields)
      relationships = nearby_relationships(object_ids)
      object_ids |= relationships.flat_map { |item| [item['from_object'], item['to_object']] }
      objects = @objects.select { |item| object_ids.include?(item.fetch('id')) }
                        .first(@limits.fetch(:objects)).map { |item| compact_object(item) }

      deep_freeze(
        version: 1, objects: objects, fields: fields, metrics: compact_semantics(metrics),
        dimensions: compact_semantics(dimensions), relationships: compact_relationships(relationships)
      )
    end

    private

    def ranked(records, terms, limit)
      matches = records.filter_map do |record|
        score = relevance(record, terms)
        [score, record.fetch('id'), record] if score.positive?
      end
      matches.sort_by { |score, id, _record| [-score, id] }.first(limit).map(&:last)
    end

    def ranked_fields(terms) # rubocop:disable Metrics/AbcSize
      candidates = @objects.flat_map do |object|
        object.fetch('fields').filter_map do |field|
          record = field.merge('id' => "#{object.fetch('id')}.#{field.fetch('id')}", 'object_id' => object.fetch('id'))
          score = relevance(record, terms)
          [score, record.fetch('id'), record] if score.positive?
        end
      end
      candidates.sort_by { |score, id, _record| [-score, id] }.first(@limits.fetch(:fields)).map do |_score, _id, field|
        field.slice('id', 'object_id', 'display_name', 'type', 'description')
      end
    end

    def relevant_object_ids(terms, metrics, dimensions, fields)
      direct = ranked(@objects, terms, @limits.fetch(:objects)).map { |item| item.fetch('id') }
      semantic = (metrics + dimensions).map { |item| item.fetch('field').split('.', 2).first }
      (direct + semantic + fields.map { |item| item.fetch('object_id') }).uniq
    end

    def nearby_relationships(object_ids)
      return [] if object_ids.empty?

      nearby = @relationships.select do |item|
        item['approved_for_planning'] == true &&
          (object_ids.include?(item.fetch('from_object')) || object_ids.include?(item.fetch('to_object')))
      end
      nearby.sort_by { |item| item.fetch('id') }.first(@limits.fetch(:relationships))
    end

    def relevance(record, terms)
      names = [record['id'], record['display_name'], *record.fetch('aliases', [])].compact
      names.sum do |name|
        candidate = tokens(name)
        exact = terms.include?(name.to_s.downcase) ? 20 : 0
        exact + ((candidate & terms).length * 3)
      end
    end

    def tokens(value)
      normalized = value.to_s.downcase
      words = normalized.scan(/[[:alnum:]_]+/)
      (words + [normalized.strip]).reject(&:empty?).uniq
    end

    def compact_object(item)
      item.slice('id', 'display_name', 'metadata_status')
    end

    def compact_semantics(records)
      records.map do |item|
        item.slice('id', 'display_name', 'field', 'native_grain', 'aggregation', 'aliases', 'warnings')
      end
    end

    def compact_relationships(records)
      records.map { |item| item.slice('id', 'from_object', 'to_object', 'cardinality') }
    end

    def deep_freeze(value)
      case value
      when Hash then value.each do |key, item|
        deep_freeze(key)
        deep_freeze(item)
      end
      when Array then value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end
  end
end
