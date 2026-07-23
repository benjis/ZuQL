# frozen_string_literal: true

require 'yaml'

module ZuQL
  # Resolves canonical metadata into safe Data Query physical identifiers.
  class DataQueryRegistry # rubocop:disable Metrics/ClassLength
    MAPPING_CONFIDENCE = %w[user_observed convention_derived].freeze
    FIELD_TYPES = %w[unknown string fixed integer decimal boolean date datetime].freeze
    DEFAULT_PATHS = {
      data_sources: File.expand_path('../../data/canonical/data_sources.yml', __dir__),
      objects: File.expand_path('../../data/canonical/objects.yml', __dir__),
      relationships: File.expand_path('../../data/canonical/relationships.yml', __dir__),
      metrics: File.expand_path('../../data/canonical/metrics.yml', __dir__)
    }.freeze

    def initialize(paths: DEFAULT_PATHS)
      @data_sources = load_index(paths, :data_sources, 'data_sources')
      @objects = load_index(paths, :objects, 'objects')
      @relationships = load_index(paths, :relationships, 'relationships')
      @metrics = load_index(paths, :metrics, 'metrics')
    rescue Psych::Exception, KeyError, TypeError => e
      raise CompilationError.new(
        "Invalid Data Query registry: #{e.message}",
        details: { kind: 'registry', reason: e.class.name }
      ), cause: e
    end

    def object(id)
      source = fetch(@data_sources, id, 'object')
      raise_metadata('object', id, 'not queryable') unless source.fetch('queryable') == true

      mapping = source.fetch('names').fetch('data_query')
      confidence = validate_mapping!(id, mapping)
      physical = physical_name(mapping.fetch('name'), kind: 'object', id: id)
      object_metadata(id, physical, mapping, confidence)
    rescue KeyError, TypeError => e
      raise_malformed('object', id, e)
    end

    def field(qualified_id)
      object_id, field_id = qualified_id.split('.', 2)
      object_record = fetch(@objects, object_id, 'object')
      record = object_record.fetch('fields').find { |field| field.fetch('id') == field_id }
      raise_metadata('field', qualified_id, 'unknown') unless record
      type = record.fetch('type', 'unknown').to_s.downcase
      raise_metadata('field', qualified_id, 'unsupported type') unless FIELD_TYPES.include?(type)

      field_metadata(qualified_id, object_id, record, type)
    rescue KeyError, TypeError => e
      raise_malformed('field', qualified_id, e)
    end

    def metric(id)
      record = fetch(@metrics, id, 'metric')
      {
        id: id, field: record.fetch('field'), native_grain: record.fetch('native_grain'),
        aggregation: record.fetch('aggregation')
      }.freeze
    rescue KeyError, TypeError => e
      raise_malformed('metric', id, e)
    end

    def relationship(id)
      record = fetch(@relationships, id, 'relationship')
      raise_metadata('relationship', id, 'not approved for planning') unless record['approved_for_planning'] == true

      join = record.fetch('join')
      {
        id: id, from_object: record.fetch('from_object'), to_object: record.fetch('to_object'),
        from_field: join.fetch('from_field'), to_field: join.fetch('to_field')
      }.freeze
    rescue KeyError, TypeError => e
      raise_malformed('relationship', id, e)
    end

    private

    def object_metadata(id, physical, mapping, confidence)
      {
        id: id, physical_name: physical, verified: mapping.fetch('verified'), confidence: confidence,
        warnings: mapping_warnings(id, physical, mapping).freeze
      }.freeze
    end

    def validate_mapping!(id, mapping)
      confidence = mapping.fetch('confidence')
      raise_metadata('object', id, 'unsupported mapping confidence') unless MAPPING_CONFIDENCE.include?(confidence)
      verified = mapping.fetch('verified')
      raise_metadata('object', id, 'invalid mapping verification') unless [true, false].include?(verified)
      if mapping.fetch('verified') && confidence != 'user_observed'
        raise_metadata('object', id, 'inconsistent mapping verification')
      end
      confidence
    end

    def field_metadata(qualified_id, object_id, record, type)
      {
        id: qualified_id, object_id: object_id,
        physical_name: physical_name(record.fetch('display_name'), kind: 'field', id: qualified_id),
        type: type, filterable: record.fetch('filterable', true), selectable: record.fetch('selectable', true)
      }.freeze
    end

    def load_index(paths, path_key, collection)
      index(YAML.safe_load_file(paths.fetch(path_key)).fetch(collection))
    end

    def index(records)
      records.to_h { |record| [record.fetch('id'), record] }.freeze
    end

    def fetch(records, id, kind)
      records.fetch(id) { raise_metadata(kind, id, 'unknown') }
    end

    def physical_name(value, kind:, id:)
      name = value.to_s.gsub(/[^A-Za-z0-9]/, '')
      return name if name.match?(/\A[A-Za-z][A-Za-z0-9]*\z/)

      raise_metadata(kind, id, 'unsafe physical name')
    end

    def mapping_warnings(id, physical, mapping)
      return [] if mapping.fetch('verified') == true

      ["Data Query object #{id} uses convention-derived physical name #{physical}."]
    end

    def raise_metadata(kind, id, reason)
      raise CompilationError.new(
        "Invalid Data Query #{kind} metadata: #{id} (#{reason})",
        details: { kind: kind, id: id, reason: reason }
      )
    end

    def raise_malformed(kind, id, error)
      raise CompilationError.new(
        "Invalid Data Query #{kind} metadata: #{id} (malformed)",
        details: { kind: kind, id: id, reason: error.message }
      ), cause: error
    end
  end
end
