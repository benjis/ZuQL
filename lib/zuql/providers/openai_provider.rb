# frozen_string_literal: true

require 'net/http'
require 'uri'

module ZuQL
  module Providers
    # OpenAI Responses API adapter with strict JSON schema output and bounded I/O.
    class OpenAIProvider # rubocop:disable Metrics/ClassLength
      DEFAULT_ENDPOINT = 'https://api.openai.com/v1/responses'
      RETRYABLE_STATUS = [408, 409, 429, 500, 502, 503, 504].freeze

      def self.from_env(env: ENV, client: nil) # rubocop:disable Metrics/MethodLength
        new(
          api_key: env.fetch('OPENAI_API_KEY'), model: env.fetch('ZUQL_OPENAI_MODEL', 'gpt-5.6-sol'),
          endpoint: env.fetch('ZUQL_OPENAI_ENDPOINT', DEFAULT_ENDPOINT), client: client,
          open_timeout: Integer(env.fetch('ZUQL_PROVIDER_OPEN_TIMEOUT', '5')),
          read_timeout: Integer(env.fetch('ZUQL_PROVIDER_READ_TIMEOUT', '30')),
          max_attempts: Integer(env.fetch('ZUQL_PROVIDER_MAX_ATTEMPTS', '3')),
          max_response_bytes: Integer(env.fetch('ZUQL_PROVIDER_MAX_RESPONSE_BYTES', '65536'))
        )
      rescue KeyError, ArgumentError => e
        raise InterpretationProviderError.new(
          'Live provider configuration is invalid', details: { reason: 'invalid_provider_configuration' }
        ), cause: e
      end

      def initialize( # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists
        api_key:, model:, endpoint: DEFAULT_ENDPOINT, client: nil, open_timeout: 5, read_timeout: 30,
        max_attempts: 3, max_response_bytes: 65_536
      )
        raise ArgumentError, 'api_key and model are required' if [api_key, model].any? { |value| value.to_s.empty? }

        bounds = [open_timeout, read_timeout, max_attempts, max_response_bytes]
        raise ArgumentError, 'provider bounds must be positive' unless bounds.all? { |value| positive_integer?(value) }

        @api_key = api_key.dup.freeze
        @model = model.dup.freeze
        @endpoint = URI.parse(endpoint)
        raise ArgumentError, 'endpoint must use HTTPS' unless @endpoint.is_a?(URI::HTTPS)

        @client = client || NetHttpClient.new
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @max_attempts = max_attempts
        @max_response_bytes = max_response_bytes
      end

      def complete(prompt:, response_schema:, **_context)
        response = request_with_retry(request_body(prompt, response_schema))
        parse_response(response)
      rescue InterpretationProviderError
        raise
      rescue StandardError => e
        raise sanitized_error('provider_failure'), cause: e
      end

      private

      def request_body(prompt, schema)
        JSON.generate(
          model: @model, input: prompt,
          text: {
            format: {
              type: 'json_schema', name: 'zuql_model_query_intent', strict: true,
              schema: strict_schema(schema)
            }
          }
        )
      end

      def strict_schema(value, property_name = nil)
        case value
        when Hash then strict_object(value, property_name)
        when Array then value.map { |item| strict_schema(item) }
        else value
        end
      end

      def strict_object(value, property_name)
        copy = value.to_h { |key, item| [key, strict_schema(item, key)] }
        copy['required'] = copy.fetch('properties').keys if copy['type'] == 'object' && copy.key?('properties')
        copy['type'] = Array(copy.fetch('type')) | ['null'] if property_name == 'requested_limit'
        copy
      end

      def request_with_retry(body) # rubocop:disable Metrics/MethodLength
        attempts = 0
        begin
          attempts += 1
          response = @client.post(
            @endpoint, body: body, headers: headers, open_timeout: @open_timeout, read_timeout: @read_timeout,
                       max_response_bytes: @max_response_bytes
          )
          status = Integer(response.fetch(:status))
          raise RetryableFailure if RETRYABLE_STATUS.include?(status)
          raise sanitized_error('provider_rejected_request') unless status.between?(200, 299)

          response.fetch(:body)
        rescue RetryableFailure, Timeout::Error, Errno::ECONNRESET, EOFError
          retry if attempts < @max_attempts
          raise sanitized_error('provider_unavailable')
        end
      end

      def parse_response(body) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        raise sanitized_error('response_too_large') if body.bytesize > @max_response_bytes

        payload = JSON.parse(body)
        message = payload.fetch('output', []).find { |item| item['type'] == 'message' }
        content = message&.fetch('content', [])&.find { |item| item['type'] == 'output_text' }
        text = content&.fetch('text', nil)
        raise sanitized_error('invalid_provider_response') unless text.is_a?(String)

        remove_nullable_defaults(text)
      rescue JSON::ParserError
        raise sanitized_error('invalid_provider_response')
      end

      def remove_nullable_defaults(text)
        payload = JSON.parse(text)
        payload.delete('requested_limit') if payload['requested_limit'].nil?
        JSON.generate(payload)
      rescue JSON::ParserError
        text
      end

      def headers
        { 'Authorization' => "Bearer #{@api_key}", 'Content-Type' => 'application/json' }
      end

      def sanitized_error(reason)
        InterpretationProviderError.new('Natural-language provider failed', details: { reason: reason })
      end

      def positive_integer?(value)
        value.is_a?(Integer) && value.positive?
      end

      class RetryableFailure < StandardError; end
      private_constant :RetryableFailure

      class NetHttpClient
        def post( # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
          uri, body:, headers:, open_timeout:, read_timeout:, max_response_bytes:
        )
          request = Net::HTTP::Post.new(uri, headers)
          request.body = body
          response = Net::HTTP.start(
            uri.host, uri.port, use_ssl: true, open_timeout: open_timeout, read_timeout: read_timeout
          ) { |http| http.request(request) }
          response_body = response.body.to_s
          if response_body.bytesize > max_response_bytes
            raise InterpretationProviderError.new(
              'Natural-language provider failed', details: { reason: 'response_too_large' }
            )
          end

          { status: response.code, body: response_body }
        end
      end
      private_constant :NetHttpClient
    end
  end
end
