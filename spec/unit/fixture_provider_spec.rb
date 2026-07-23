# frozen_string_literal: true

require 'tmpdir'

RSpec.describe ZuQL::Providers::FixtureProvider do
  let(:response) do
    {
      'intent' => 'detail_export', 'requested_entities' => ['subscription'],
      'requested_fields' => [{ 'concept' => 'subscription status' }],
      'filters' => [], 'metrics' => [], 'dimensions' => []
    }
  end

  it 'returns frozen JSON for an exact supported question' do
    provider = described_class.new(fixtures: { 'List active subscriptions' => response })

    json = provider.complete(
      question: 'List active subscriptions', prompt: 'ignored', response_schema: {}
    )

    expect(JSON.parse(json).fetch('intent')).to eq('detail_export')
    expect(json).to be_frozen
  end

  it 'defensively copies caller-owned fixtures' do
    question = +'List active subscriptions'
    fixtures = { question => response }
    provider = described_class.new(fixtures: fixtures)
    response['intent'] = 'count'
    question << ' changed'

    json = provider.complete(
      question: 'List active subscriptions', prompt: 'ignored', response_schema: {}
    )

    expect(JSON.parse(json).fetch('intent')).to eq('detail_export')
  end

  it 'exposes immutable questions in fixture order' do
    question = +'First question'
    provider = described_class.new(fixtures: { question => response, 'Second question' => response })
    question << ' changed'

    expect(provider.questions).to eq(['First question', 'Second question'])
    expect(provider.questions).to be_frozen
    expect(provider.questions).to all(be_frozen)
    expect(described_class.from_yaml.questions.length).to be >= 23
    expect(described_class.from_yaml.questions.last(3)).to all(match(/instructions|Snowflake|QUESTION_JSON/))
  end

  it 'fails closed for an unknown question without reflecting it' do
    provider = described_class.new(fixtures: {})

    expect do
      provider.complete(question: 'secret question', prompt: 'ignored', response_schema: {})
    end.to raise_error(ZuQL::InterpretationProviderError) { |error|
      expect(error.message).not_to include('secret question')
      expect(error.details.values).not_to include('secret question')
    }
  end

  it 'loads fixtures from safe YAML and ignores golden expectations' do
    yaml = <<~YAML
      version: 1
      questions:
        - question: List active subscriptions
          response:
            intent: detail_export
            requested_entities: [subscription]
            requested_fields: [{concept: subscription status}]
            filters: []
            metrics: []
            dimensions: []
          expected_query_spec:
            backend_preference: data_query
    YAML

    with_yaml(yaml) do |path|
      provider = described_class.from_yaml(path)
      json = provider.complete(question: 'List active subscriptions', prompt: 'ignored', response_schema: {})
      expect(JSON.parse(json)).to eq(response)
    end
  end

  it 'rejects duplicate questions and malformed YAML roots' do
    duplicate = <<~YAML
      version: 1
      questions:
        - {question: Same, response: {}}
        - {question: Same, response: {}}
    YAML

    with_yaml(duplicate) do |path|
      expect { described_class.from_yaml(path) }
        .to raise_error(ZuQL::InterpretationProviderError, 'Fixture data is invalid')
    end
    with_yaml('- not-a-mapping') do |path|
      expect { described_class.from_yaml(path) }
        .to raise_error(ZuQL::InterpretationProviderError, 'Fixture data is invalid')
    end
  end

  it 'rejects whitespace-only questions from memory and YAML' do
    expect { described_class.new(fixtures: { '   ' => response }) }
      .to raise_error(ZuQL::InterpretationProviderError, 'Fixture data is invalid')

    yaml = "version: 1\nquestions:\n  - question: '   '\n    response: {}\n"
    with_yaml(yaml) do |path|
      expect { described_class.from_yaml(path) }
        .to raise_error(ZuQL::InterpretationProviderError, 'Fixture data is invalid')
    end
  end

  def with_yaml(content)
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'fixtures.yml')
      File.write(path, content)
      yield path
    end
  end
end
