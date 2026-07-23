# frozen_string_literal: true

require 'digest'
require 'json'
require 'yaml'

module ZuQL
  # Audits the checked-in public canonical metadata without source HTML access.
  class MetadataAudit
    DEFAULT_ROOT = File.expand_path('../..', __dir__)
    COLLECTIONS = {
      data_sources: ['data/canonical/data_sources.yml', 'data_sources'],
      objects: ['data/canonical/objects.yml', 'objects'],
      relationships: ['data/canonical/relationships.yml', 'relationships'],
      metrics: ['data/canonical/metrics.yml', 'metrics'],
      dimensions: ['data/canonical/dimensions.yml', 'dimensions'],
      domains: ['data/canonical/support_matrix.yml', 'domains']
    }.freeze
    CARDINALITIES = %w[one_to_one one_to_many many_to_one many_to_many].freeze
    MAPPING_CONFIDENCE = %w[convention_derived user_observed].freeze

    def initialize(root: DEFAULT_ROOT)
      @root = File.expand_path(root)
      @errors = []
    end

    def report
      @errors = []
      @object_index = nil
      load_collections
      validate_unique_ids
      validate_registry_alignment
      validate_relationships
      validate_semantics
      validate_mappings
      validate_support_matrix
      validate_source_checksums
      deep_freeze(build_report)
    rescue Psych::Exception, Errno::ENOENT, KeyError, TypeError => e
      failure_report('malformed_artifact', e.class.name)
    end

    def validate!
      result = report
      return result if result.fetch('errors').empty?

      raise MetadataValidationError.new(details: { errors: result.fetch('errors') })
    end

    def render
      "#{JSON.pretty_generate(report)}\n"
    end

    private

    def load_collections
      @documents = {}
      @collections = COLLECTIONS.to_h do |name, (relative_path, collection)|
        document = YAML.safe_load_file(path(relative_path))
        @documents[name] = document
        add_error('schema_version', name, document['schema_version']) unless document['schema_version'] == 1
        records = document.fetch(collection)
        raise TypeError, "#{collection} must be an array" unless records.instance_of?(Array)

        [name, records]
      end
    end

    def validate_unique_ids
      @collections.each do |name, records|
        duplicate_values(records.map { |record| record.fetch('id') }).each do |id|
          add_error('duplicate_id', name, id)
        end
      end
      objects.each do |object|
        duplicate_values(object.fetch('fields').map { |field| field.fetch('id') }).each do |id|
          add_error('duplicate_field', object.fetch('id'), id)
        end
      end
    end

    def validate_registry_alignment
      object_ids = objects.map { |object| object.fetch('id') }.sort
      source_ids = data_sources.map { |source| source.fetch('id') }.sort
      add_error('registry_mismatch', 'objects', 'data_sources') unless object_ids == source_ids
    end

    def validate_relationships
      relationships.each do |relationship|
        id = relationship.fetch('id')
        from = object_index[relationship.fetch('from_object')]
        to = object_index[relationship.fetch('to_object')]
        add_error('unknown_relationship_object', id, 'from_object') unless from
        add_error('unknown_relationship_object', id, 'to_object') unless to
        unless CARDINALITIES.include?(relationship.fetch('cardinality'))
          add_error('invalid_cardinality', id, relationship.fetch('cardinality'))
        end
        validate_approved_relationship(relationship, from, to) if relationship['approved_for_planning'] == true
      end
    end

    def validate_approved_relationship(relationship, from, to)
      id = relationship.fetch('id')
      join = relationship.fetch('join')
      validate_join_field(id, 'from_field', join.fetch('from_field'), from)
      validate_join_field(id, 'to_field', join.fetch('to_field'), to)
      unless relationship['confidence'] == 'reviewed'
        add_error('unreviewed_relationship', id, relationship['confidence'])
      end
      provenance = relationship.fetch('provenance')
      %w[kind path sha256 review_status].each do |key|
        add_error('missing_provenance', id, key) if provenance[key].to_s.empty?
      end
      add_error('invalid_provenance_hash', id, 'sha256') unless provenance['sha256'].to_s.match?(/\A[0-9a-f]{64}\z/)
    end

    def validate_join_field(relationship_id, key, field_id, object)
      valid = object&.fetch('fields')&.any? { |field| field.fetch('id') == field_id }
      add_error('unknown_join_field', relationship_id, key) unless valid
    end

    def validate_semantics
      metrics.each do |metric|
        validate_field_reference('metric', metric.fetch('id'), metric.fetch('field'))
        grain = metric.fetch('native_grain')
        add_error('unknown_metric_grain', metric.fetch('id'), grain) unless object_index.key?(grain)
        add_error('missing_metric_alias', metric.fetch('id'), 'aliases') if metric.fetch('aliases').empty?
      end
      dimensions.each do |dimension|
        validate_field_reference('dimension', dimension.fetch('id'), dimension.fetch('field'))
        add_error('missing_dimension_alias', dimension.fetch('id'), 'aliases') if dimension.fetch('aliases').empty?
      end
    end

    def validate_field_reference(kind, id, reference)
      object_id, field_id = reference.to_s.split('.', 2)
      object = object_index[object_id]
      valid = object && field_id && object.fetch('fields').any? { |field| field.fetch('id') == field_id }
      add_error('unknown_semantic_field', "#{kind}:#{id}", reference) unless valid
    end

    def validate_mappings
      data_sources.each do |source|
        id = source.fetch('id')
        mapping = source.fetch('names').fetch('data_query')
        confidence = mapping.fetch('confidence')
        add_error('invalid_mapping_confidence', id, confidence) unless MAPPING_CONFIDENCE.include?(confidence)
        unless [true, false].include?(mapping['verified'])
          add_error('invalid_mapping_verified', id, mapping['verified'])
        end
        add_error('missing_physical_name', id, 'data_query') if mapping['name'].to_s.empty?
        next unless mapping['verified'] == true && confidence != 'user_observed'

        add_error('inconsistent_mapping_status', id, confidence)
      end
    end

    def validate_source_checksums
      extracted_path = 'data/extracted/zuora_data_sources.yml'
      actual = Digest::SHA256.file(path(extracted_path)).hexdigest
      %i[data_sources objects].each do |document|
        expected = @documents.fetch(document).dig('sources', 'extracted_data_sources', 'sha256')
        add_error('stale_source_checksum', document, expected) unless expected == actual
      end
      @extracted_checksum = actual
    end

    def validate_support_matrix
      fixture_questions = YAML.safe_load_file(path('data/fixtures/query_interpretations.yml'))
                              .fetch('questions').map { |entry| entry.fetch('question') }
      domains.each do |domain|
        id = domain.fetch('id')
        validate_support_status(domain, id)
        validate_support_references(domain, id)
        domain.fetch('representative_questions').each do |question|
          add_error('unknown_representative_question', id, question) unless fixture_questions.include?(question)
        end
      end
    end

    def validate_support_status(domain, id)
      add_error('invalid_support_status', id, domain['status']) unless %w[supported partial].include?(domain['status'])
      if domain['status'] == 'partial' && domain.fetch('limitations').empty?
        add_error('missing_support_limitation', id, 'limitations')
      end
      add_error('missing_capability', id, 'capabilities') if domain.fetch('capabilities').empty?
    end

    def validate_support_references(domain, id)
      support_reference_sets.each do |key, known|
        domain.fetch(key).each do |reference|
          add_error('unknown_support_reference', id, "#{key}:#{reference}") unless known.include?(reference)
        end
      end
    end

    def support_reference_sets
      {
        'objects' => object_index.keys,
        'relationships' => relationships.select { |item| item['approved_for_planning'] }.map { |item| item['id'] },
        'metrics' => metrics.map { |item| item['id'] },
        'dimensions' => dimensions.map { |item| item['id'] }
      }
    end

    def build_report
      {
        'schema_version' => 1,
        'status' => @errors.empty? ? 'valid' : 'invalid',
        'counts' => counts,
        'mapping_status' => mapping_status,
        'quality' => quality,
        'source_checksums' => { 'extracted_data_sources' => @extracted_checksum },
        'errors' => @errors.sort_by { |error| error.values.map(&:to_s) }
      }
    end

    def counts
      {
        'data_sources' => data_sources.size, 'objects' => objects.size,
        'fields' => objects.sum { |object| object.fetch('fields').size },
        'relationships' => relationships.size,
        'approved_relationships' => relationships.count { |record| record['approved_for_planning'] == true },
        'metrics' => metrics.size, 'dimensions' => dimensions.size, 'domains' => domains.size
      }
    end

    def mapping_status
      mappings = data_sources.map { |source| source.fetch('names').fetch('data_query') }
      {
        'verified' => mappings.count { |mapping| mapping['verified'] == true },
        'unverified' => mappings.count { |mapping| mapping['verified'] == false },
        'user_observed' => mappings.count { |mapping| mapping['confidence'] == 'user_observed' },
        'convention_derived' => mappings.count { |mapping| mapping['confidence'] == 'convention_derived' }
      }
    end

    def quality
      fields = objects.flat_map { |object| object.fetch('fields') }
      extracted_document = YAML.safe_load_file(path('data/extracted/zuora_data_sources.yml'))
      raise TypeError, 'extracted registry must be a mapping' unless extracted_document.instance_of?(Hash)

      extracted = extracted_document.fetch('data_sources')
      raise TypeError, 'extracted data_sources must be an array' unless extracted.instance_of?(Array)

      {
        'fields_with_unknown_type' => fields.count { |field| field['type'] == 'unknown' },
        'fields_without_description' => fields.count { |field| field['description'].to_s.strip.empty? },
        'incomplete_data_sources' => data_sources.count { |source| source['metadata_status'] == 'incomplete' },
        'extraction_warnings' => extracted.sum { |source| source.fetch('warnings').size }
      }
    end

    def failure_report(reason, detail)
      deep_freeze(
        'schema_version' => 1, 'status' => 'invalid', 'counts' => {}, 'mapping_status' => {}, 'quality' => {},
        'source_checksums' => {}, 'errors' => [{ 'reason' => reason, 'subject' => 'registry', 'detail' => detail }]
      )
    end

    def add_error(reason, subject, detail)
      @errors << { 'reason' => reason.to_s, 'subject' => subject.to_s, 'detail' => detail.to_s }
    end

    def duplicate_values(values)
      values.tally.select { |_value, count| count > 1 }.keys.sort
    end

    def object_index
      @object_index ||= objects.to_h { |object| [object.fetch('id'), object] }
    end

    def data_sources = @collections.fetch(:data_sources)
    def objects = @collections.fetch(:objects)
    def relationships = @collections.fetch(:relationships)
    def metrics = @collections.fetch(:metrics)
    def dimensions = @collections.fetch(:dimensions)
    def domains = @collections.fetch(:domains)

    def path(relative_path)
      File.join(@root, relative_path)
    end

    def deep_freeze(value)
      case value
      when Hash
        value.each do |key, item|
          deep_freeze(key)
          deep_freeze(item)
        end
      when Array then value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end
  end
end
