# frozen_string_literal: true

module ZuQL
  class Error < StandardError; end

  class ContractError < Error
    attr_reader :details

    def initialize(message = 'Invalid contract input', details: {})
      @details = details.freeze
      super(message)
    end
  end

  class SerializationError < Error; end
  class ExtractionError < Error; end

  class ExportError < Error
    attr_reader :details

    def initialize(message = 'Export failed', details: {})
      @details = copy_and_freeze(details)
      super(message)
    end

    private

    def copy_and_freeze(value)
      copy = case value
             when Hash then value.to_h { |key, item| [copy_and_freeze(key), copy_and_freeze(item)] }
             when Array then value.map { |item| copy_and_freeze(item) }
             when String then value.dup
             else value
             end
      copy.freeze
    end
  end

  class InterpretationError < Error
    attr_reader :details

    def initialize(message = 'Natural-language interpretation failed', details: {})
      @details = deep_copy_and_freeze(details)
      super(message)
    end

    private

    def deep_copy_and_freeze(value)
      copied = case value
               when Hash then value.to_h { |key, item| [key, deep_copy_and_freeze(item)] }
               when Array then value.map { |item| deep_copy_and_freeze(item) }
               when String then value.dup
               else value
               end
      copied.freeze
    end
  end

  class InvalidQuestionError < InterpretationError; end
  class InterpretationProviderError < InterpretationError; end
  class InvalidModelOutputError < InterpretationError; end

  class InterpretationLimitError < InterpretationError
    def initialize(requested:, maximum:)
      super(
        'Requested result limit exceeds the configured maximum',
        details: { requested: requested, maximum: maximum }
      )
    end
  end

  class ResolutionError < Error
    attr_reader :details

    def initialize(message = 'Resolution failed', details: {})
      @details = details.freeze
      super(message)
    end
  end

  class UnknownConceptError < ResolutionError
    def initialize(concept, kind:)
      super("Unknown #{kind} concept: #{concept}", details: { concept: concept, kind: kind })
    end
  end

  class AmbiguousConceptError < ResolutionError
    def initialize(concept, kind:, candidates:)
      super(
        "Ambiguous #{kind} concept: #{concept}",
        details: { concept: concept, kind: kind, candidates: candidates.freeze }
      )
    end
  end

  class UnreachableObjectsError < ResolutionError
    def initialize(object_ids)
      super('Canonical objects are not connected by approved relationships', details: { object_ids: object_ids.freeze })
    end
  end

  class PlanningError < Error
    attr_reader :details

    def initialize(message = 'Planning failed', details: {})
      @details = details.freeze
      super(message)
    end
  end

  class MissingRootObjectError < PlanningError
    def initialize(intent)
      super('No root object can be selected', details: { intent: intent })
    end
  end

  class InvalidQueryShapeError < PlanningError
    def initialize(intent, reason)
      super(
        "Invalid #{intent} query shape: #{reason}",
        details: { intent: intent, reason: reason }
      )
    end
  end

  class IncompatibleMetricGrainsError < PlanningError
    def initialize(metric_grains)
      grains = metric_grains.transform_keys(&:to_sym).freeze
      super('Aggregate metrics have incompatible native grains', details: { metric_grains: grains })
    end
  end

  class JoinPathError < PlanningError
    def initialize(root_object, target_objects)
      super(
        'Required objects are not connected by approved relationships',
        details: { root_object: root_object, target_objects: target_objects.freeze }
      )
    end
  end

  class AmbiguousJoinPathError < PlanningError
    def initialize(root_object, target_object, candidates:)
      super(
        'Multiple equally safe reviewed join paths are available',
        details: {
          root_object: root_object, target_object: target_object,
          candidates: candidates.map(&:freeze).freeze
        }
      )
    end
  end

  class FanoutRiskError < PlanningError
    def initialize(metric:, native_grain:, edge:, path:)
      super(
        'Join path can duplicate an aggregate metric',
        details: {
          metric: metric, native_grain: native_grain,
          relationship: edge.fetch(:id), traverse_from: edge.fetch(:traverse_from),
          traverse_to: edge.fetch(:traverse_to), path: path.freeze
        }
      )
    end
  end

  class IncompatibleFilterError < PlanningError
    def initialize(field:, field_type:, operator:, value:, reason:)
      super(
        "Filter #{operator} is incompatible with #{field} (#{field_type})",
        details: {
          field: field, field_type: field_type, operator: operator,
          value: value, reason: reason
        }
      )
    end
  end

  class ValidationError < Error; end

  class MetadataValidationError < ValidationError
    attr_reader :details

    def initialize(message = 'Canonical metadata validation failed', details: {})
      @details = details.freeze
      super(message)
    end
  end

  class SafetyValidationError < ValidationError
    attr_reader :details

    def initialize(message = 'SQL safety validation failed', details: {})
      @details = deep_copy_and_freeze(details)
      super(message)
    end

    private

    def deep_copy_and_freeze(value)
      copied = case value
               when Hash then value.to_h { |key, item| [key, deep_copy_and_freeze(item)] }
               when Array then value.map { |item| deep_copy_and_freeze(item) }
               when String then value.dup
               else value
               end
      copied.freeze
    end
  end

  class CompilationError < Error
    attr_reader :details

    def initialize(message = 'Compilation failed', details: {})
      @details = details.freeze
      super(message)
    end
  end
end
