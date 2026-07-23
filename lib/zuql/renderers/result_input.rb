# frozen_string_literal: true

module ZuQL
  module Renderers
    module ResultInput
      REAL_ATTRIBUTES = Contracts::Base.instance_method(:attributes)
      REAL_CLASS = Kernel.instance_method(:class)
      REAL_FROZEN = Kernel.instance_method(:frozen?)
      REAL_INSTANCE_OF = Kernel.instance_method(:instance_of?)
      REAL_SINGLETON_METHODS = Kernel.instance_method(:singleton_methods)
      SCALAR_CLASSES = [NilClass, TrueClass, FalseClass, Integer, Float, Symbol].freeze
      CONTRACT_CLASSES = [
        Contracts::PipelineResult, Contracts::QuerySpec, Contracts::RequestedField,
        Contracts::ConceptFilter, Contracts::Resolution, Contracts::QueryPlan,
        Contracts::Selection, Contracts::Join, Contracts::PlanFilter,
        Contracts::CompiledQuery, Contracts::QueryExplanation
      ].freeze

      module_function

      def validate!(result)
        valid = exact_instance?(result, Contracts::PipelineResult) && deeply_frozen?(result)
        return result if valid

        raise ContractError.new('Renderer requires an immutable PipelineResult', details: { input: 'result' })
      end

      def deeply_frozen?(value)
        return false unless safe_object?(value)

        frozen_value?(value)
      end

      def frozen_value?(value)
        case value
        when Contracts::Base then trusted_contract?(value)
        when Hash then trusted_hash?(value)
        when Array then trusted_array?(value)
        when String then exact_instance?(value, String)
        else SCALAR_CLASSES.include?(REAL_CLASS.bind_call(value))
        end
      end

      def trusted_hash?(value)
        exact_instance?(value, Hash) && frozen_mapping?(value)
      end

      def trusted_array?(value)
        exact_instance?(value, Array) && value.all? { |item| deeply_frozen?(item) }
      end

      def safe_object?(value)
        REAL_FROZEN.bind_call(value) && REAL_SINGLETON_METHODS.bind_call(value).empty?
      end

      def trusted_contract?(value)
        CONTRACT_CLASSES.include?(REAL_CLASS.bind_call(value)) && frozen_mapping?(REAL_ATTRIBUTES.bind_call(value))
      end

      def exact_instance?(value, klass)
        REAL_INSTANCE_OF.bind_call(value, klass)
      end

      def frozen_mapping?(mapping)
        trusted_hash = exact_instance?(mapping, Hash) && REAL_FROZEN.bind_call(mapping) &&
                       REAL_SINGLETON_METHODS.bind_call(mapping).empty?
        trusted_hash && mapping.all? do |key, item|
          deeply_frozen?(key) && deeply_frozen?(item)
        end
      end
      private_class_method :deeply_frozen?
      private_class_method :frozen_value?
      private_class_method :safe_object?
      private_class_method :trusted_contract?
      private_class_method :trusted_hash?
      private_class_method :trusted_array?
      private_class_method :exact_instance?
      private_class_method :frozen_mapping?
    end
  end
end
