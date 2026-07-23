# frozen_string_literal: true

require 'stringio'

RSpec.describe 'reviewed CLI golden output' do # rubocop:disable RSpec/MultipleDescribes
  let(:provider) { ZuQL::Providers::FixtureProvider.from_yaml }
  let(:result) do
    ZuQL::Pipeline.new(interpreter: ZuQL::NaturalLanguageInterpreter.new(provider: provider))
                  .call('Count active subscriptions')
  end

  it 'matches the versioned terminal and JSON fixtures exactly' do
    outputs = {
      'txt' => ZuQL::Renderers::TerminalRenderer.new.render(result),
      'json' => ZuQL::Renderers::JsonRenderer.new.render(result)
    }

    outputs.each do |extension, output|
      path = File.expand_path("../fixtures/cli/count_active_subscriptions.#{extension}", __dir__)
      expect(output).to eq(File.read(path, encoding: Encoding::UTF_8))
    end
  end
end

RSpec.describe 'Phase M6 CLI scenario goldens' do
  let(:provider) { ZuQL::Providers::FixtureProvider.from_yaml }
  let(:pipeline) do
    ZuQL::Pipeline.new(interpreter: ZuQL::NaturalLanguageInterpreter.new(provider: provider))
  end

  {
    'Show 50 account numbers and names' => ['detail_export', 'FROM "Account"', 'LIMIT 50'],
    'Count active subscriptions' => ['count', 'COUNT(DISTINCT', 'WHERE'],
    'Show MRR by account' => ['aggregate', 'SUM(', 'GROUP BY'],
    'List payments after 2026-01-01' => ['detail_export', 'WHERE', "'2026-01-01'"],
    'Show payment amount by payment date for 30 rows' => ['aggregate', 'GROUP BY', 'LIMIT 30'],
    'List product rate plans and their products' => ['detail_export', 'INNER JOIN', 'product.product_rate_plan']
  }.each do |question, expected|
    it "renders the reviewed #{question.inspect} scenario" do
      result = pipeline.call(question)
      output = ZuQL::Renderers::TerminalRenderer.new.render(result)

      expect(result.query_spec.intent).to eq(expected.first)
      expect(output).to include(*expected.drop(1))
      expect(output).to include('Public canonical model limitation', 'Mapping status', 'SQL')
    end
  end

  it 'rejects the reviewed fan-out scenario without partial output' do
    out = StringIO.new
    err = StringIO.new
    cli = ZuQL::CLI.new(provider: provider, pipeline: pipeline)

    expect(cli.run(['Show invoice charge amount by subscription'], out: out, err: err)).to eq(5)
    expect([out.string, err.string]).to eq(['', "Unsafe plan rejected.\n"])
  end
end
