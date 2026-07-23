# frozen_string_literal: true

require 'yaml'

module ZuQL
  # Loads curated semantic metadata and performs strict, typed concept lookup.
  class SemanticRegistry
    DEFAULT_PATHS = {
      metrics: File.expand_path('../../data/canonical/metrics.yml', __dir__),
      dimensions: File.expand_path('../../data/canonical/dimensions.yml', __dir__),
      objects: File.expand_path('../../data/canonical/objects.yml', __dir__)
    }.freeze

    def initialize(paths: DEFAULT_PATHS)
      @index = Hash.new { |kinds, kind| kinds[kind] = Hash.new { |keys, key| keys[key] = [] } }
      @records = Hash.new { |records, kind| records[kind] = {} }
      load_semantics(paths.fetch(:metrics), 'metrics', :metric)
      load_semantics(paths.fetch(:dimensions), 'dimensions', :dimension)
      load_objects(paths.fetch(:objects))
    end

    def metric(id)
      record(:metric, id)
    end

    def dimension(id)
      record(:dimension, id)
    end

    def object(id)
      record(:object, id)
    end

    def field(id)
      record(:field, id)
    end

    def resolve(concept, kind) # rubocop:disable Metrics/AbcSize
      normalized = normalize(concept)
      matches = @index.fetch(kind, {}).fetch(normalized, [])
      raise UnknownConceptError.new(concept, kind: kind) if matches.empty?

      highest_confidence = matches.map { |match| match.fetch(:confidence) }.max
      preferred = matches.select { |match| match.fetch(:confidence) == highest_confidence }
      candidates = preferred.map { |match| match.fetch(:id) }.uniq.sort
      raise AmbiguousConceptError.new(concept, kind: kind, candidates: candidates) if candidates.length > 1

      preferred.first
    end

    private

    def load_semantics(path, collection, kind)
      YAML.safe_load_file(path).fetch(collection).each do |record|
        @records[kind][record.fetch('id')] = symbolize(record).freeze
        index_semantic(record, kind)
      end
    end

    def index_semantic(record, kind)
      field = record.fetch('field')
      base = {
        id: record.fetch('id'), kind: kind.to_s, object_id: field.split('.', 2).first,
        field: field, warnings: record.fetch('warnings', []).freeze
      }
      add(kind, record.fetch('id'), base, 1.0)
      add(kind, record.fetch('display_name'), base, 0.95)
      record.fetch('aliases', []).each { |name| add(kind, name, base, 0.9) }
    end

    def load_objects(path)
      YAML.safe_load_file(path).fetch('objects').each { |object| index_object(object) }
    end

    def index_object(object) # rubocop:disable Metrics/AbcSize
      @records[:object][object.fetch('id')] = object_record(object)
      base = {
        id: object.fetch('id'), kind: 'object', object_id: object.fetch('id'),
        field: nil, warnings: [].freeze
      }
      add(:object, object.fetch('id'), base, 1.0)
      add(:object, object.fetch('display_name'), base, 0.95)
      object.fetch('aliases', []).each { |name| add(:object, name, base, 0.9) }
      object.fetch('fields').each { |field| index_field(object, field) }
    end

    def object_record(object)
      {
        id: object.fetch('id'), display_name: object.fetch('display_name'),
        default_grain: object.fetch('id')
      }.freeze
    end

    def index_field(object, field)
      qualified_id = "#{object.fetch('id')}.#{field.fetch('id')}"
      base = {
        id: qualified_id, kind: 'field', object_id: object.fetch('id'),
        field: qualified_id, type: field.fetch('type', 'unknown'), warnings: [].freeze
      }
      @records[:field][qualified_id] = base.freeze
      add(:field, qualified_id, base, 1.0)
      add(:field, field.fetch('id'), base, 1.0)
      add(:field, field.fetch('display_name'), base, 0.95)
      field.fetch('aliases', []).each { |name| add(:field, name, base, 0.9) }
    end

    def add(kind, key, base, confidence)
      @index[kind][normalize(key)] << base.merge(confidence: confidence).freeze
    end

    def normalize(value)
      value.to_s.strip.downcase.gsub(/\s+/, ' ')
    end

    def record(kind, id)
      @records.fetch(kind).fetch(id) do
        raise UnknownConceptError.new(id, kind: kind)
      end
    end

    def symbolize(record)
      record.to_h do |key, value|
        frozen_value = value.is_a?(Array) ? value.dup.freeze : value
        [key.to_sym, frozen_value]
      end
    end
  end
end
