# frozen_string_literal: true

RSpec.describe 'renderer input and Markdown safety' do
  let(:provider) { ZuQL::Providers::FixtureProvider.from_yaml }
  let(:result) do
    ZuQL::Pipeline.new(interpreter: ZuQL::NaturalLanguageInterpreter.new(provider: provider))
                  .call('Count active subscriptions')
  end
  let(:renderers) do
    [ZuQL::Renderers::TerminalRenderer.new, ZuQL::Renderers::JsonRenderer.new,
     ZuQL::Renderers::MarkdownRenderer.new]
  end

  it 'rejects untyped, extended, singleton, and mutable results' do
    subclass = Class.new(ZuQL::Contracts::PipelineResult).new(result.to_h).freeze
    singleton = ZuQL::Contracts::PipelineResult.new(result.to_h)
    singleton.define_singleton_method(:tampered?) { true }
    singleton.freeze
    mutable = ZuQL::Contracts::PipelineResult.new(result.to_h)

    [{}, subclass, singleton, mutable].each do |invalid|
      renderers.each { |renderer| expect { renderer.render(invalid) }.to raise_error(ZuQL::ContractError) }
    end
  end

  it 'rejects a forged result that hides singleton methods and attributes' do
    forged = ZuQL::Contracts::PipelineResult.new(
      result.to_h.merge(compiled_query: result.compiled_query.to_h.merge(sql: 'ATTACKER SQL'))
    )
    forged.define_singleton_method(:singleton_methods) { [] }
    forged.define_singleton_method(:attributes) { {}.freeze }
    forged.define_singleton_method(:frozen?) { true }
    forged.freeze

    renderers.each do |renderer|
      expect { renderer.render(forged) }.to raise_error(ZuQL::ContractError)
    end

    forged_attributes = ZuQL::Contracts::PipelineResult.new(
      result.to_h.merge(compiled_query: result.compiled_query.to_h.merge(sql: 'ATTACKER SQL 2'))
    )
    attributes = forged_attributes.attributes
    attributes.define_singleton_method(:frozen?) { true }
    attributes.define_singleton_method(:all?) { true }
    forged_attributes.freeze

    renderers.each do |renderer|
      expect { renderer.render(forged_attributes) }.to raise_error(ZuQL::ContractError)
    end
  end

  it 'escapes Markdown text and chooses a fence longer than SQL backtick runs' do
    hostile = ZuQL::Contracts::PipelineResult.from_h(
      result.to_h.merge(question: "# heading [link](target) `tick` <script>&\nsafe\n~~~html\ninjected\n~~~\n===",
                        compiled_query: result.compiled_query.to_h.merge(sql: "SELECT '```', '````'"))
    )
    output = ZuQL::Renderers::MarkdownRenderer.new.render(hostile)

    expect(output).to include('\\# heading \\[link\\]\\(target\\) \\`tick\\`')
    expect(output).to include('&lt;script&gt;&amp;')
    expect(output).to include('\\n')
    expect(output).not_to include("\n~~~html\n")
    expect(output).not_to include("\nsafe\n===")
    expect(output).to include("`````sql\nSELECT '```', '````'\n`````")
  end
end
