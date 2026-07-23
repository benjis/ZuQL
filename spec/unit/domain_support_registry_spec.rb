# frozen_string_literal: true

require 'tmpdir'

RSpec.describe ZuQL::DomainSupportRegistry do
  subject(:registry) { described_class.new }

  it 'publishes the explicit immutable eight-domain MVP boundary' do
    expect(registry.domains.map { |domain| domain.fetch('id') }).to eq(
      %w[subscriptions product_catalog orders invoicing payments credit_memos debit_memos usage]
    )
    expect(registry.domains).to be_frozen
    expect(registry.domains).to all(be_frozen)
    expect(registry.domain('subscriptions').fetch('status')).to eq('supported')
    expect(registry.domain('usage')).to include('status' => 'partial')
    expect(registry.domain('usage').fetch('limitations')).not_to be_empty
  end

  it 'fails closed for unknown domains and malformed or duplicate records' do
    expect { registry.domain('snowflake') }.to raise_error(ZuQL::MetadataValidationError)

    Dir.mktmpdir do |directory|
      path = File.join(directory, 'support.yml')
      File.write(path, YAML.dump('schema_version' => 1, 'domains' => [{ 'id' => 'same' }, { 'id' => 'same' }]))
      expect { described_class.new(path: path) }.to raise_error(ZuQL::MetadataValidationError)

      File.write(path, "domains: [\n")
      expect { described_class.new(path: path) }.to raise_error(ZuQL::MetadataValidationError)
    end
  end
end
