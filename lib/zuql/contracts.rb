# frozen_string_literal: true

require 'json'
require 'dry-struct'

module ZuQL
  module Contracts
    class Base < Dry::Struct
      transform_keys(&:to_sym)
      schema schema.strict

      class << self
        def from_h(input)
          new(deep_symbolize(input)).freeze
        rescue Dry::Struct::Error, Dry::Types::ConstraintError, KeyError, TypeError => e
          raise ContractError.new(e.message, details: { contract: name }), cause: e
        end

        def from_json(json)
          from_h(JSON.parse(json))
        rescue JSON::ParserError => e
          raise SerializationError, e.message
        end

        private

        def deep_symbolize(value)
          case value
          when Hash then value.to_h { |key, item| [key.to_sym, deep_symbolize(item)] }
          when Array then value.map { |item| deep_symbolize(item) }
          else value
          end
        end
      end

      def to_h
        attributes.to_h { |key, value| [key, serialize(value)] }
      end

      def to_json(*options)
        JSON.generate(to_h, *options)
      end

      def id
        attributes.key?(:id) ? self[:id] : super
      end

      private

      def serialize(value)
        case value
        when Base then value.to_h
        when Array then value.map { |item| serialize(item) }
        when Hash then value.to_h { |key, item| [key, serialize(item)] }
        else value
        end
      end
    end

    class SourceReference < Base
      attribute :kind, Types::NonEmptyString
      attribute :url, Types::NonEmptyString
    end

    class ExtractedField < Base
      attribute :display_name, Types::NonEmptyString
      attribute? :source_type, Types::Strict::String.optional
      attribute? :description, Types::Strict::String.optional
      attribute :source_order, Types::PositiveInteger
    end

    class ExtractedObject < Base
      attribute :label, Types::NonEmptyString
      attribute :role, Types::Strict::String.enum('base', 'related')
      attribute :fields, Types::Strict::Array.of(ExtractedField)
    end

    class ExtractedDataSource < Base
      attribute :name, Types::NonEmptyString
      attribute :url, Types::NonEmptyString
      attribute :feature_notes, Types::StringList.default([].freeze)
      attribute :availability_notes, Types::StringList.default([].freeze)
      attribute :source_order, Types::PositiveInteger
    end

    class CanonicalObject < Base
      attribute :id, Types::Identifier
      attribute :display_name, Types::NonEmptyString
      attribute :description, Types::Strict::String
      attribute :primary_key, Types::Identifier
      attribute :default_grain, Types::Identifier
      attribute :aliases, Types::StringList.default([].freeze)
      attribute :sources, Types::Strict::Array.of(SourceReference).default([].freeze)
    end

    previous_verbose = $VERBOSE
    $VERBOSE = nil

    class CanonicalField < Base
      attribute :id, Types::Identifier
      attribute :object_id, Types::Identifier
      attribute :canonical_name, Types::Identifier
      attribute :display_name, Types::NonEmptyString
      attribute :canonical_type, Types::NonEmptyString
      attribute :description, Types::Strict::String
      attribute? :semantic_type, Types::Strict::String.optional
      attribute :aliases, Types::StringList.default([].freeze)
      attribute :filterable, Types::Strict::Bool
      attribute :selectable, Types::Strict::Bool
      attribute :sources, Types::Strict::Array.of(SourceReference).default([].freeze)

      def object_id
        self[:object_id]
      end
    end

    $VERBOSE = previous_verbose

    class CanonicalRelationship < Base
      attribute :id, Types::Identifier
      attribute :from_object, Types::Identifier
      attribute :to_object, Types::Identifier
      attribute :from_field, Types::Identifier
      attribute :to_field, Types::Identifier
      attribute :cardinality, Types::Strict::String.enum('one_to_one', 'one_to_many', 'many_to_one', 'many_to_many')
      attribute :default_join_type, Types::Strict::String.enum('inner', 'left')
      attribute :fanout_risk, Types::Strict::String.enum('none', 'low', 'medium', 'high')
      attribute :confidence, Types::Strict::String.enum('reviewed', 'candidate')
      attribute :sources, Types::Strict::Array.of(SourceReference).default([].freeze)
      attribute :feature_requirements, Types::StringList.default([].freeze)
    end

    class RequestedField < Base
      attribute :concept, Types::NonEmptyString
    end

    class ConceptFilter < Base
      attribute :concept, Types::NonEmptyString
      attribute :operator, Types::Strict::String.enum(
        'equals', 'not_equals', 'in', 'not_in', 'gt', 'gte', 'lt', 'lte', 'contains'
      )
      attribute :value, Types::JsonFilterValue
    end

    class ModelQueryIntent < Base
      attribute :intent, Types::Strict::String.enum('detail_export', 'aggregate', 'count')
      attribute :requested_entities, Types::StringList
      attribute :requested_fields, Types::Strict::Array.of(RequestedField)
      attribute :filters, Types::Strict::Array.of(ConceptFilter).default([].freeze)
      attribute :metrics, Types::StringList.default([].freeze)
      attribute :dimensions, Types::StringList.default([].freeze)
      attribute :order_by, Types::Strict::Array.default([].freeze)
      attribute? :requested_limit, Types::PositiveInteger
    end

    class QuerySpec < Base
      attribute :intent, Types::Strict::String.enum('detail_export', 'aggregate', 'count')
      attribute :requested_entities, Types::StringList
      attribute :requested_fields, Types::Strict::Array.of(RequestedField)
      attribute :filters, Types::Strict::Array.of(ConceptFilter).default([].freeze)
      attribute :metrics, Types::StringList.default([].freeze)
      attribute :dimensions, Types::StringList.default([].freeze)
      attribute :group_by, Types::StringList.default([].freeze)
      attribute :order_by, Types::Strict::Array.default([].freeze)
      attribute :limit, Types::PositiveInteger
      attribute :backend_preference, Types::Strict::String.enum('auto', 'data_query', 'snowflake')

      class << self
        def from_h(input)
          query_spec = super(deep_copy(input))
          deep_freeze(query_spec)
        end

        private

        def deep_copy(value)
          case value
          when Hash then value.to_h { |key, item| [key, deep_copy(item)] }
          when Array then value.map { |item| deep_copy(item) }
          when String then value.dup
          else value
          end
        end

        def deep_freeze(value)
          case value
          when Base then deep_freeze_attributes(value)
          when Hash then deep_freeze_hash(value)
          when Array then value.each { |item| deep_freeze(item) }
          end
          value.freeze
        end

        def deep_freeze_attributes(value)
          attributes = value.attributes
          attributes.each_value { |item| deep_freeze(item) }
          attributes.freeze
        end

        def deep_freeze_hash(value)
          value.each do |key, item|
            deep_freeze(key)
            deep_freeze(item)
          end
        end
      end
    end

    class Resolution < Base
      attribute :input, Types::NonEmptyString
      attribute :resolved_to, Types::NonEmptyString
      attribute :kind, Types::Strict::String.enum('field', 'metric', 'dimension', 'object')
      attribute :confidence, Types::Confidence
      attribute :alternatives, Types::StringList.default([].freeze)
    end

    class ResolvedQuery < Base
      attribute :query_spec, QuerySpec
      attribute :resolutions, Types::Strict::Array.of(Resolution)
      attribute :warnings, Types::StringList.default([].freeze)
    end

    class Selection < Base
      attribute? :field, Types::Strict::String.optional
      attribute? :metric, Types::Strict::String.optional
      attribute :alias, Types::Identifier
    end

    class Join < Base
      attribute :relationship, Types::NonEmptyString
      attribute :join_type, Types::Strict::String.enum('inner', 'left')
    end

    class PlanFilter < Base
      attribute :field, Types::NonEmptyString
      attribute :operator, Types::Strict::String.enum('=', '!=', '>', '>=', '<', '<=', 'IN', 'NOT IN', 'LIKE')
      attribute :value, Types::Any
    end

    class QueryPlan < Base
      attribute :backend, Types::Strict::String.enum('data_query', 'snowflake')
      attribute :root_object, Types::Identifier
      attribute :select, Types::Strict::Array.of(Selection)
      attribute :joins, Types::Strict::Array.of(Join).default([].freeze)
      attribute :filters, Types::Strict::Array.of(PlanFilter).default([].freeze)
      attribute :group_by, Types::StringList.default([].freeze)
      attribute :order_by, Types::Strict::Array.default([].freeze)
      attribute :limit, Types::PositiveInteger
      attribute :grain, Types::Identifier
      attribute :warnings, Types::StringList.default([].freeze)
    end

    class CompiledQuery < Base
      attribute :backend, Types::Strict::String.enum('data_query', 'snowflake')
      attribute :sql, Types::NonEmptyString
      attribute :warnings, Types::StringList.default([].freeze)

      class << self
        def from_h(input)
          compiled = super(deep_copy(input))
          compiled.backend.freeze
          compiled.sql.freeze
          compiled.warnings.each(&:freeze)
          compiled.warnings.freeze
          compiled
        end

        private

        def deep_copy(value)
          case value
          when Hash then value.to_h { |key, item| [key, deep_copy(item)] }
          when Array then value.map { |item| deep_copy(item) }
          when String then value.dup
          else value
          end
        end
      end
    end

    class QueryExplanation < Base
      attribute :summary, Types::NonEmptyString
      attribute :interpretation, Types::NonEmptyString.default('Interpretation unavailable.')
      attribute :resolutions, Types::StringList
      attribute :filters, Types::StringList.default([].freeze)
      attribute :metrics, Types::StringList.default([].freeze)
      attribute :root, Types::NonEmptyString
      attribute :joins, Types::StringList
      attribute :inserted_bridges, Types::StringList.default([].freeze)
      attribute :grain, Types::NonEmptyString
      attribute :grouping, Types::NonEmptyString
      attribute :backend, Types::NonEmptyString.default('Backend unavailable.')
      attribute :assumptions, Types::StringList.default([].freeze)
      attribute :mapping_status, Types::NonEmptyString.default('Mapping status unavailable.')
      attribute :limitation, Types::NonEmptyString.default(
        'ZuQL uses a public canonical model; tenant-specific fields, features, and mappings may differ.'
      )
      attribute :sql, Types::NonEmptyString.default('SQL unavailable.')
    end

    class PipelineResult < Base
      attribute :question, Types::NonEmptyString
      attribute :query_spec, QuerySpec
      attribute :resolutions, Types::Strict::Array.of(Resolution)
      attribute :plan, QueryPlan
      attribute :compiled_query, CompiledQuery
      attribute :warnings, Types::StringList
      attribute :explanation, QueryExplanation

      class << self
        def from_h(input)
          result = super(deep_copy(input))
          deep_freeze(result)
        end

        private

        def deep_copy(value)
          case value
          when Base then deep_copy(value.to_h)
          when Hash then value.to_h { |key, item| [deep_copy(key), deep_copy(item)] }
          when Array then value.map { |item| deep_copy(item) }
          when String then value.dup
          else value
          end
        end

        def deep_freeze(value)
          case value
          when Base then deep_freeze_attributes(value)
          when Hash then deep_freeze_hash(value)
          when Array then value.each { |item| deep_freeze(item) }
          end
          value.freeze
        end

        def deep_freeze_attributes(value)
          attributes = value.attributes
          attributes.each_value { |item| deep_freeze(item) }
          attributes.freeze
        end

        def deep_freeze_hash(value)
          value.each do |key, item|
            deep_freeze(key)
            deep_freeze(item)
          end
        end
      end
    end
  end
end
