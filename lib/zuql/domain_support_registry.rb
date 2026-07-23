# frozen_string_literal: true

require 'yaml'

module ZuQL
  # Exposes the explicit, reviewed MVP support boundary by Zuora domain.
  class DomainSupportRegistry
    DEFAULT_PATH = File.expand_path('../../data/canonical/support_matrix.yml', __dir__)

    def initialize(path: DEFAULT_PATH)
      records = load_records(path)
      @domains = deep_freeze(records.map { |record| deep_copy(record) })
      @index = @domains.to_h { |record| [record.fetch('id'), record] }.freeze
      raise KeyError, 'duplicate domain ID' unless @index.size == @domains.size
    rescue Psych::Exception, Errno::ENOENT, KeyError, TypeError => e
      raise MetadataValidationError.new(
        'Invalid domain support registry', details: { reason: e.class.name }
      ), cause: e
    end

    attr_reader :domains

    def domain(id)
      @index.fetch(id) do
        raise MetadataValidationError.new('Unknown domain support record', details: { id: id })
      end
    end

    private

    def load_records(path)
      document = YAML.safe_load_file(path)
      raise KeyError, 'unsupported support-matrix schema' unless document.fetch('schema_version') == 1

      document.fetch('domains').tap do |records|
        raise TypeError, 'domains must be an array' unless records.instance_of?(Array)
      end
    end

    def deep_copy(value)
      case value
      when Hash then value.to_h { |key, item| [deep_copy(key), deep_copy(item)] }
      when Array then value.map { |item| deep_copy(item) }
      when String then value.dup
      else value
      end
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
