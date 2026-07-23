# frozen_string_literal: true

require 'stringio'
require 'tmpdir'

RSpec.describe ZuQL::CLI do
  let(:provider) { ZuQL::Providers::FixtureProvider.from_yaml }
  let(:result) do
    ZuQL::Pipeline.new(interpreter: ZuQL::NaturalLanguageInterpreter.new(provider: provider))
                  .call('Count active subscriptions')
  end

  it 'supports mutually exclusive informational modes without running the pipeline' do
    pipeline = Object.new.tap { |object| object.define_singleton_method(:call) { |_| raise 'called' } }
    cli = described_class.new(provider: provider, pipeline: pipeline)

    [['--help'], ['--version'], ['--list-examples'], ['--list-domains']].each do |argv|
      expect(cli.run(argv, out: StringIO.new, err: StringIO.new)).to eq(0)
    end
    err = StringIO.new
    expect(cli.run(['--help', 'question'], out: StringIO.new, err: err)).to eq(2)
    expect(err.string).to eq("Usage error.\n")
  end

  it 'lists only end-to-end examples in support-matrix order' do
    out = StringIO.new
    status = described_class.new(provider: provider, pipeline: Object.new).run(
      ['--list-examples'], out: out, err: StringIO.new
    )

    expect(status).to eq(0)
    questions = ZuQL::DomainSupportRegistry.new.domains.flat_map do |domain|
      domain.fetch('representative_questions')
    end
    expect(out.string).to eq("#{questions.join("\n")}\n")
    expect(out.string).not_to include('Show invoice charge amount by subscription')
  end

  it 'reports domain status, capabilities, and limitations' do
    out = StringIO.new
    status = described_class.new(provider: provider, pipeline: Object.new).run(
      ['--list-domains'], out: out, err: StringIO.new
    )

    expect(status).to eq(0)
    expect(out.string).to include('subscriptions [supported]')
    expect(out.string).to include('usage [partial]')
    expect(out.string).to include('capabilities: detail, filter')
    expect(out.string).to include('Usage is standalone')
  end

  it 'exports before emitting the terminal report' do
    Dir.mktmpdir do |directory|
      out = StringIO.new
      json_path = File.join(directory, 'result.json')
      markdown_path = File.join(directory, 'result.md')
      result_value = result
      cli = described_class.new(provider: provider, pipeline: Object.new.tap do |object|
        object.define_singleton_method(:call) { |_| result_value }
      end)

      status = cli.run(['--json', json_path, '--markdown', markdown_path, 'Count active subscriptions'],
                       out: out, err: StringIO.new)

      expect(status).to eq(0)
      expect(JSON.parse(File.read(json_path))).to eq(JSON.parse(result.to_json))
      expect(File.read(markdown_path)).to include('# ZuQL Query Explanation')
      expect(out.string).to include("Question\nCount active subscriptions")
    end
  end

  it 'returns stable usage and runtime statuses without partial output' do
    cli = described_class.new(provider: provider, pipeline: Object.new)
    [['--unknown'], [], %w[one two], ['--json', 'same', '--markdown', 'same', 'question']].each do |argv|
      out = StringIO.new
      expect(cli.run(argv, out: out, err: StringIO.new)).to eq(2)
      expect(out.string).to be_empty
    end

    broken = Object.new.tap { |object| object.define_singleton_method(:call) { |_| raise 'secret SQL' } }
    out = StringIO.new
    err = StringIO.new
    expect(described_class.new(provider: provider, pipeline: broken).run(['question'], out: out, err: err)).to eq(1)
    expect(out.string).to be_empty
    expect(err.string).to eq("Internal error.\n")
  end

  it 'accepts one explicit provider mode and rejects conflicting modes' do
    result_value = result
    pipeline = Object.new.tap { |object| object.define_singleton_method(:call) { |_| result_value } }
    cli = described_class.new(provider: provider, pipeline: pipeline)

    expect(cli.run(['--offline', 'question'], out: StringIO.new, err: StringIO.new)).to eq(0)
    expect(cli.run(%w[--offline --live question], out: StringIO.new, err: StringIO.new)).to eq(2)
  end

  it 'uses stable sanitized statuses for product failure categories' do
    risky_edge = { id: 'a.b', traverse_from: 'a', traverse_to: 'b' }
    cases = [
      [ZuQL::UnknownConceptError.new('secret', kind: :field), 3, "Unsupported question.\n"],
      [ZuQL::AmbiguousConceptError.new('secret', kind: :field, candidates: %w[a b]), 4, "Ambiguous concept.\n"],
      [ZuQL::FanoutRiskError.new(metric: 'm', native_grain: 'a', edge: risky_edge, path: ['a.b']),
       5, "Unsafe plan rejected.\n"],
      [ZuQL::InterpretationProviderError.new('secret', details: { reason: 'provider_unavailable' }),
       6, "Provider failed.\n"]
    ]

    cases.each do |error, status, message|
      pipeline = Object.new.tap { |object| object.define_singleton_method(:call) { |_| raise error } }
      out = StringIO.new
      err = StringIO.new
      expect(described_class.new(provider: provider, pipeline: pipeline).run(['question'], out: out, err: err))
        .to eq(status)
      expect([out.string, err.string]).to eq(['', message])
    end
  end
end
