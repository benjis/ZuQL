# frozen_string_literal: true

RSpec.describe 'Phase 16 renderers' do
  let(:provider) { ZuQL::Providers::FixtureProvider.from_yaml }
  let(:result) do
    ZuQL::Pipeline.new(interpreter: ZuQL::NaturalLanguageInterpreter.new(provider: provider))
                  .call('Count active subscriptions')
  end

  it 'renders terminal sections in a stable order with one trailing newline' do
    no_warnings = ZuQL::Contracts::PipelineResult.from_h(result.to_h.merge(warnings: []))
    output = ZuQL::Renderers::TerminalRenderer.new.render(no_warnings)

    expect(output).to be_frozen
    expect(output.scan(/\n\z/).length).to eq(1)
    expect(output).to include("Question\nCount active subscriptions")
    expect(output).to include("Join path\nNo joins required.")
    expect(output).to include("Warnings\nNone")
    expect(output.index('Explanation')).to be < output.index('SQL')
  end

  it 'renders canonical pretty JSON' do
    expect(ZuQL::Renderers::JsonRenderer.new.render(result))
      .to eq("#{JSON.pretty_generate(result.to_h)}\n")
  end

  it 'renders Markdown headings, bullets, and SQL' do
    output = ZuQL::Renderers::MarkdownRenderer.new.render(result)

    expect(output).to include('# ZuQL Query Explanation')
    expect(output).to include('- No joins required\\.')
    expect(output).to include("```sql\n#{result.compiled_query.sql}\n```")
    expect(output.end_with?("\n")).to be(true)
  end
end
