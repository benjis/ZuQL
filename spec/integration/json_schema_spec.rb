# frozen_string_literal: true

require 'json_schemer'

RSpec.describe 'public JSON Schemas' do
  schemas = %w[query_spec resolved_query query_plan compiled_query model_query_intent pipeline_result]

  schemas.each do |name|
    it "accepts the valid #{name} fixture" do
      schema = JSONSchemer.schema(Pathname("schemas/#{name}.schema.json"))
      fixture = JSON.parse(File.read("spec/fixtures/contracts/#{name}.json"))
      expect(schema.valid?(fixture)).to be(true)
    end

    it "rejects unknown properties in #{name}" do
      schema = JSONSchemer.schema(Pathname("schemas/#{name}.schema.json"))
      fixture = JSON.parse(File.read("spec/fixtures/contracts/#{name}.json")).merge('unexpected' => true)
      expect(schema.valid?(fixture)).to be(false)
    end
  end

  it 'rejects structured model filter values' do
    schema = JSONSchemer.schema(Pathname('schemas/model_query_intent.schema.json'))
    fixture = JSON.parse(File.read('spec/fixtures/contracts/model_query_intent.json'))
    fixture['filters'] = [
      { 'concept' => 'status', 'operator' => 'equals', 'value' => { 'sql' => 'DROP TABLE Account' } }
    ]

    expect(schema.valid?(fixture)).to be(false)
  end

  it 'keeps QuerySpec filter value shapes aligned with its Ruby contract' do
    schema = JSONSchemer.schema(Pathname('schemas/query_spec.schema.json'))
    fixture = JSON.parse(File.read('spec/fixtures/contracts/query_spec.json'))
    fixture['filters'] = [
      { 'concept' => 'status', 'operator' => 'equals', 'value' => { 'sql' => 'DROP TABLE Account' } }
    ]

    expect(schema.valid?(fixture)).to be(false)
    expect { ZuQL::Contracts::QuerySpec.from_h(fixture) }.to raise_error(ZuQL::ContractError)
  end
end
