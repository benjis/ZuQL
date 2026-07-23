# frozen_string_literal: true

module ZuQL
  class NaturalLanguageInterpreter
    class Configuration
      attr_reader :provider, :prompt, :retriever, :default_limit, :max_limit, :max_attempts, :max_response_bytes

      def initialize( # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
        provider:, prompt:, retriever:, default_limit:, max_limit:, max_attempts:, max_response_bytes:
      )
        validate_provider!(provider)
        validate_prompt!(prompt)
        validate_limits!(default_limit, max_limit)
        validate_attempts!(max_attempts)
        raise ArgumentError, 'retriever must respond to retrieve' unless retriever.respond_to?(:retrieve)
        unless positive_integer?(max_response_bytes)
          raise ArgumentError,
                'max_response_bytes must be a positive integer'
        end

        @provider = provider
        @prompt = prompt
        @retriever = retriever
        @default_limit = default_limit
        @max_limit = max_limit
        @max_attempts = max_attempts
        @max_response_bytes = max_response_bytes
      end

      private

      def validate_provider!(provider)
        raise ArgumentError, 'provider must respond to complete' unless provider.respond_to?(:complete)
      end

      def validate_prompt!(prompt)
        return if prompt.instance_of?(QueryPrompt) && prompt.singleton_methods.empty?

        raise ArgumentError, 'prompt must be a plain QueryPrompt'
      end

      def validate_limits!(default_limit, max_limit)
        valid = positive_integer?(default_limit) && positive_integer?(max_limit)
        return if valid && default_limit <= max_limit

        raise ArgumentError, 'limits must be positive integers and default_limit must not exceed max_limit'
      end

      def validate_attempts!(max_attempts)
        raise ArgumentError, 'max_attempts must be a positive integer' unless positive_integer?(max_attempts)
      end

      def positive_integer?(value)
        value.instance_of?(Integer) && value.positive?
      end
    end

    private_constant :Configuration
  end
end
