# frozen_string_literal: true

RSpec.describe ZuQL::Providers::OpenAIProvider do
  let(:client_class) do
    Class.new do
      attr_reader :calls

      def initialize(responses)
        @responses = responses
        @calls = []
      end

      def post(uri, **options)
        @calls << { uri: uri, options: options }
        response = @responses.shift
        raise response if response.is_a?(Exception)

        response
      end
    end
  end

  it 'requests strict structured output without putting credentials in the body' do
    model_output = '{"intent":"count"}'
    body = JSON.generate(
      output: [
        { type: 'reasoning' },
        { type: 'message', content: [{ type: 'output_text', text: model_output }] }
      ]
    )
    client = client_class.new([{ status: 200, body: body }])
    provider = described_class.new(api_key: 'secret-key', model: 'test-model', client: client)

    result = provider.complete(prompt: 'trusted prompt', response_schema: { 'type' => 'object' })

    request = client.calls.fetch(0).fetch(:options)
    payload = JSON.parse(request.fetch(:body))
    expect(result).to eq(model_output)
    expect(payload.dig('text', 'format', 'strict')).to be(true)
    expect(payload.dig('text', 'format', 'schema')).to eq('type' => 'object')
    expect(request.fetch(:body)).not_to include('secret-key')
    expect(request.fetch(:headers).fetch('Authorization')).to eq('Bearer secret-key')
  end

  it 'retries transient failures and sanitizes the exhausted error' do
    client = client_class.new([Timeout::Error.new('secret timeout'), { status: 503, body: 'secret' }])
    provider = described_class.new(api_key: 'key', model: 'model', client: client, max_attempts: 2)

    expect { provider.complete(prompt: 'prompt', response_schema: {}) }
      .to raise_error(ZuQL::InterpretationProviderError) { |error|
        expect(error.details).to eq(reason: 'provider_unavailable')
        expect(error.message).not_to include('secret')
      }
    expect(client.calls.length).to eq(2)
  end

  it 'rejects oversized and malformed responses with stable reasons' do
    oversized = client_class.new([{ status: 200, body: 'x' * 11 }])
    malformed = client_class.new([{ status: 200, body: '{}' }])

    expect do
      described_class.new(api_key: 'key', model: 'model', client: oversized, max_response_bytes: 10)
                     .complete(prompt: 'prompt', response_schema: {})
    end.to raise_error(ZuQL::InterpretationProviderError) { |error|
      expect(error.details).to eq(reason: 'response_too_large')
    }
    expect do
      described_class.new(api_key: 'key', model: 'model', client: malformed)
                     .complete(prompt: 'prompt', response_schema: {})
    end.to raise_error(ZuQL::InterpretationProviderError) { |error|
      expect(error.details).to eq(reason: 'invalid_provider_response')
    }
  end

  it 'validates environment-only configuration without exposing missing names' do
    expect { described_class.from_env(env: {}) }
      .to raise_error(ZuQL::InterpretationProviderError) { |error|
        expect(error.details).to eq(reason: 'invalid_provider_configuration')
      }
  end
end
