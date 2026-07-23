# frozen_string_literal: true

RSpec.describe ZuQL::NaturalLanguageInterpreter do
  let(:provider_class) do
    Class.new do
      attr_reader :calls

      def initialize(responses, error)
        @responses = responses.dup
        @error = error
        @calls = []
      end

      def complete(question:, prompt:, response_schema:)
        @calls << { question: question, prompt: prompt, response_schema: response_schema }
        raise @error if @error

        @responses.shift
      end
    end
  end

  it 'builds a Data Query QuerySpec with application-controlled defaults' do
    provider = provider_for(model_json(intent: 'detail_export'))

    result = described_class.new(provider: provider).interpret('List active subscriptions')

    expect(result).to be_a(ZuQL::Contracts::QuerySpec)
    expect(result).to be_frozen
    expect(result.backend_preference).to eq('data_query')
    expect(result.limit).to eq(1_000)
    expect(result.group_by).to eq([])
    expect(result.order_by).to eq([])
  end

  it 'derives aggregate grouping from dimensions' do
    provider = provider_for(model_json(intent: 'aggregate', dimensions: ['account country']))

    result = described_class.new(provider: provider).interpret('MRR by account country')

    expect(result.group_by).to eq(['account country'])
  end

  it 'uses an explicitly extracted result limit' do
    provider = provider_for(model_json(intent: 'detail_export', requested_limit: 25))

    result = described_class.new(provider: provider).interpret('List 25 active subscriptions')

    expect(result.limit).to eq(25)
  end

  it 'accepts explicit sorting and date-range filters from structured output' do
    payload = JSON.parse(model_json(intent: 'aggregate', dimensions: ['invoice date']))
    payload['filters'] = [
      { 'concept' => 'invoice date', 'operator' => 'gte', 'value' => '2026-01-01' },
      { 'concept' => 'invoice date', 'operator' => 'lte', 'value' => '2026-01-31' }
    ]
    payload['order_by'] = [{ 'field' => 'invoice_date', 'direction' => 'desc' }]

    result = described_class.new(provider: provider_for(JSON.generate(payload))).interpret('Newest invoices in January')

    expect(result.filters.map(&:operator)).to eq(%w[gte lte])
    expect(result.order_by).to eq([{ field: 'invoice_date', direction: 'desc' }])
  end

  it 'rejects oversized provider output using an application-side bound' do
    response = model_json(intent: 'count') + (' ' * 20)
    provider = provider_for(response, response)

    expect { described_class.new(provider: provider, max_response_bytes: 10).interpret('Count subscriptions') }
      .to raise_error(ZuQL::InvalidModelOutputError)
  end

  it 'snapshots the question before passing it to collaborators' do
    question = +'List active subscriptions'
    provider = provider_for(model_json(intent: 'detail_export'))

    described_class.new(provider: provider).interpret(question)

    supplied = provider.calls.fetch(0).fetch(:question)
    expect(supplied).to eq(question)
    expect(supplied).not_to equal(question)
    expect(supplied).to be_frozen
  end

  it 'rejects invalid questions before calling the provider' do
    subclass = Class.new(String).new('question')
    singleton = +'question'
    singleton.define_singleton_method(:strip) { 'forged' }
    invalid_encoding = "\xFF".dup.force_encoding(Encoding::UTF_8)

    [nil, subclass, singleton, '', '   ', invalid_encoding].each do |question|
      provider = provider_for(model_json(intent: 'detail_export'))
      expect { described_class.new(provider: provider).interpret(question) }
        .to raise_error(ZuQL::InvalidQuestionError)
      expect(provider.calls).to be_empty
    end
  end

  it 'validates constructor configuration eagerly' do
    provider = provider_for(model_json(intent: 'detail_export'))

    expect { described_class.new(provider: Object.new) }.to raise_error(ArgumentError)
    expect { described_class.new(provider: provider, default_limit: 0) }.to raise_error(ArgumentError)
    expect { described_class.new(provider: provider, max_limit: 0) }.to raise_error(ArgumentError)
    expect { described_class.new(provider: provider, default_limit: 11, max_limit: 10) }
      .to raise_error(ArgumentError)
    expect { described_class.new(provider: provider, max_attempts: 0) }.to raise_error(ArgumentError)
  end

  it 'retries malformed output and returns the next valid response' do
    provider = provider_for('{', model_json(intent: 'count'))

    result = described_class.new(provider: provider).interpret('Count subscriptions')

    expect(result.intent).to eq('count')
    expect(provider.calls.length).to eq(2)
  end

  it 'rejects untrusted output shapes and reports exhausted attempts' do
    string_subclass = Class.new(String).new(model_json(intent: 'count'))
    singleton_string = +model_json(intent: 'count')
    singleton_string.define_singleton_method(:to_str) { model_json(intent: 'count') }
    invalid_outputs = [
      {}, string_subclass, singleton_string, '{', '[]',
      "#{model_json(intent: 'count')} #{model_json(intent: 'count')}",
      JSON.generate(JSON.parse(model_json(intent: 'count')).merge('sql' => 'SELECT 1'))
    ]

    invalid_outputs.each do |output|
      provider = provider_for(output, output)
      expect { described_class.new(provider: provider).interpret('Count subscriptions') }
        .to raise_error(ZuQL::InvalidModelOutputError) { |error|
          expect(error.details).to include(attempts: 2, prompt_version: 'v1')
        }
      expect(provider.calls.length).to eq(2)
    end
  end

  it 'rejects an excessive limit without retrying' do
    provider = provider_for(model_json(intent: 'detail_export', requested_limit: 10_001))

    expect { described_class.new(provider: provider).interpret('List 10001 subscriptions') }
      .to raise_error(ZuQL::InterpretationLimitError) { |error|
        expect(error.details).to eq(requested: 10_001, maximum: 10_000)
      }
    expect(provider.calls.length).to eq(1)
  end

  it 'wraps a provider exception once and preserves its cause' do
    failure = RuntimeError.new('remote response contained secret material')
    provider = provider_for(error: failure)

    expect { described_class.new(provider: provider).interpret('secret question') }
      .to raise_error(ZuQL::InterpretationProviderError) { |error|
        expect(error.cause).to equal(failure)
        expect(error.message).not_to include('secret')
        expect(error.details.to_s).not_to include('secret')
      }
    expect(provider.calls.length).to eq(1)
  end

  it 'does not wrap or retry an existing typed provider error' do
    failure = ZuQL::InterpretationProviderError.new('No fixture exists for this question')
    provider = provider_for(error: failure)

    expect { described_class.new(provider: provider).interpret('Unknown fixture') }
      .to raise_error(failure)
    expect(provider.calls.length).to eq(1)
  end

  def model_json(intent:, dimensions: [], requested_limit: nil)
    payload = {
      intent: intent, requested_entities: ['subscription'],
      requested_fields: [{ concept: 'subscription status' }],
      filters: [], metrics: [], dimensions: dimensions
    }
    payload[:requested_limit] = requested_limit if requested_limit
    JSON.generate(payload)
  end

  def provider_for(*responses, error: nil)
    provider_class.new(responses, error)
  end
end
