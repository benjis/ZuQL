# frozen_string_literal: true

require 'yaml'

RSpec.describe 'natural-language interpreter golden corpus' do
  let(:fixture_path) { 'data/fixtures/query_interpretations.yml' }
  let(:document) do
    YAML.safe_load_file(
      fixture_path, permitted_classes: [], permitted_symbols: [], aliases: false
    )
  end

  it 'converts at least twenty offline questions into exact QuerySpec values' do
    entries = document.fetch('questions')
    provider = ZuQL::Providers::FixtureProvider.from_yaml(fixture_path)
    interpreter = ZuQL::NaturalLanguageInterpreter.new(provider: provider)

    expect(entries.length).to be >= 20
    expect(entries.count { |entry| entry['security_case'] == 'prompt_injection' }).to be >= 3
    entries.each do |entry|
      actual = interpreter.interpret(entry.fetch('question')).to_h
      expected = deep_symbolize(entry.fetch('expected_query_spec'))
      expect(actual).to eq(expected), entry.fetch('question')
      expect(actual.fetch(:backend_preference)).to eq('data_query')
    end
  end

  def deep_symbolize(value)
    case value
    when Hash then value.to_h { |key, item| [key.to_sym, deep_symbolize(item)] }
    when Array then value.map { |item| deep_symbolize(item) }
    else value
    end
  end
end
