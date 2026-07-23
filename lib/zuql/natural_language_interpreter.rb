# frozen_string_literal: true

require_relative 'interpreter_configuration'

module ZuQL
  class NaturalLanguageInterpreter # rubocop:disable Metrics/ClassLength
    class ProviderOutputFailure < StandardError; end
    private_constant :ProviderOutputFailure
    DEFAULT_RETRIEVER = MetadataRetriever.new
    private_constant :DEFAULT_RETRIEVER

    def initialize( # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
      provider:, prompt: QueryPrompt.new, retriever: DEFAULT_RETRIEVER, default_limit: 1_000,
      max_limit: 10_000, max_attempts: 2, max_response_bytes: 65_536
    )
      config = Configuration.new(
        provider: provider, prompt: prompt, retriever: retriever, default_limit: default_limit,
        max_limit: max_limit, max_attempts: max_attempts, max_response_bytes: max_response_bytes
      )
      @provider = config.provider
      @prompt = config.prompt
      @retriever = config.retriever
      @default_limit = config.default_limit
      @max_limit = config.max_limit
      @max_attempts = config.max_attempts
      @max_response_bytes = config.max_response_bytes
    end

    def interpret(question)
      question_snapshot = snapshot_question(question)
      prompt = @prompt.render(question_snapshot, metadata_context: @retriever.retrieve(question_snapshot))
      interpret_with_retry(question_snapshot, prompt)
    end

    private

    def interpret_with_retry(question, prompt)
      attempts = 0

      begin
        attempts += 1
        interpret_once(question, prompt)
      rescue ProviderOutputFailure
        retry if attempts < @max_attempts

        raise exhausted_output_error(attempts)
      end
    end

    def interpret_once(question, prompt)
      model_intent = parse_model_intent(complete(question, prompt))
      validate_limit!(model_intent)
      build_query_spec(model_intent)
    end

    def exhausted_output_error(attempts)
      InvalidModelOutputError.new(
        'Provider output did not match the model intent contract',
        details: { attempts: attempts, prompt_version: @prompt.version }
      )
    end

    def snapshot_question(question)
      valid = plain_string?(question) && question.valid_encoding? && !question.strip.empty?
      raise InvalidQuestionError.new(details: { reason: 'invalid_question' }) unless valid

      String.new(question).freeze
    rescue EncodingError
      raise InvalidQuestionError.new(details: { reason: 'invalid_question' })
    end

    def complete(question, prompt)
      @provider.complete(
        question: question, prompt: prompt, response_schema: @prompt.response_schema
      )
    rescue InterpretationProviderError
      raise
    rescue StandardError => e
      raise provider_error, cause: e
    end

    def provider_error
      InterpretationProviderError.new(
        'Natural-language provider failed', details: { reason: 'provider_failure' }
      )
    end

    def parse_model_intent(response)
      raise ProviderOutputFailure unless plain_string?(response) && response.valid_encoding?
      raise ProviderOutputFailure if response.bytesize > @max_response_bytes

      payload = JSON.parse(String.new(response).freeze)
      raise ProviderOutputFailure unless payload.instance_of?(Hash) && @prompt.valid_response?(payload)

      Contracts::ModelQueryIntent.from_h(payload)
    rescue JSON::ParserError, ContractError, EncodingError
      raise ProviderOutputFailure
    end

    def validate_limit!(model_intent)
      requested_limit = model_intent.requested_limit
      return unless requested_limit && requested_limit > @max_limit

      raise InterpretationLimitError.new(requested: requested_limit, maximum: @max_limit)
    end

    def plain_string?(value)
      value.instance_of?(String) && value.singleton_methods.empty?
    end

    def build_query_spec(model_intent)
      Contracts::QuerySpec.from_h(model_attributes(model_intent).merge(application_attributes(model_intent)))
    end

    def model_attributes(model_intent)
      {
        intent: model_intent.intent,
        requested_entities: model_intent.requested_entities,
        requested_fields: model_intent.requested_fields.map(&:to_h),
        filters: model_intent.filters.map(&:to_h),
        metrics: model_intent.metrics,
        dimensions: model_intent.dimensions
      }
    end

    def application_attributes(model_intent)
      {
        group_by: model_intent.intent == 'aggregate' ? model_intent.dimensions : [],
        order_by: model_intent.order_by.map { |entry| symbolize_order(entry) },
        limit: model_intent.requested_limit || @default_limit,
        backend_preference: 'data_query'
      }
    end

    def symbolize_order(entry)
      entry.to_h { |key, value| [key.to_sym, value] }
    end
  end
end
