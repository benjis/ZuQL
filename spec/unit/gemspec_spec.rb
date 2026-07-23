# frozen_string_literal: true

RSpec.describe 'zuql gem package' do
  it 'includes every runtime natural-language interpreter asset' do
    gemspec = Gem::Specification.load('zuql.gemspec')
    required_assets = %w[
      prompts/query_spec/v1.txt
      schemas/model_query_intent.schema.json
      data/fixtures/query_interpretations.yml
      data/canonical/support_matrix.yml
      data/generated/metadata_audit.json
    ]

    expect(gemspec).not_to be_nil
    expect(gemspec.files).to include(*required_assets)
  end

  it 'packages the product and metadata-audit executables' do
    gemspec = Gem::Specification.load('zuql.gemspec')

    expect(gemspec.bindir).to eq('exe')
    expect(gemspec.executables).to include('zuql', 'zuql-audit')
    expect(gemspec.files).to include('exe/zuql', 'exe/zuql-audit')
  end
end
