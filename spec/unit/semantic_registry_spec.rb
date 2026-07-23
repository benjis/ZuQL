# frozen_string_literal: true

require 'zuql'
require 'tmpdir'

RSpec.describe ZuQL::SemanticRegistry do
  subject(:registry) { described_class.new }

  it 'resolves metric aliases after normalizing case and whitespace' do
    expect(registry.resolve('  MONTHLY   recurring revenue ', :metric)).to include(
      id: 'current_mrr', kind: 'metric', confidence: 0.9,
      field: 'rate_plan_charge.mrr'
    )
  end

  it 'assigns confidence based on the matched key source' do
    expect(registry.resolve('current_mrr', :metric)).to include(confidence: 1.0)
    expect(registry.resolve('Current MRR', :metric)).to include(confidence: 0.95)
  end

  it 'prefers a canonical ID over another record display name or alias' do
    Dir.mktmpdir do |directory|
      paths = write_registry(directory,
                             metrics: [
                               semantic_record('revenue', 'Canonical Revenue'),
                               semantic_record('other_metric', 'Revenue', aliases: ['revenue'])
                             ])

      expect(described_class.new(paths: paths).resolve('revenue', :metric)).to include(
        id: 'revenue', confidence: 1.0
      )
    end
  end

  it 'reports stable candidates when matches at the same precedence are ambiguous' do
    Dir.mktmpdir do |directory|
      paths = write_registry(directory,
                             metrics: [
                               semantic_record('z_metric', 'Zed', aliases: ['shared']),
                               semantic_record('a_metric', 'Aye', aliases: ['shared'])
                             ])

      expect { described_class.new(paths: paths).resolve('shared', :metric) }
        .to raise_error(ZuQL::AmbiguousConceptError) do |error|
          expect(error.details.fetch(:candidates)).to eq(%w[a_metric z_metric])
        end
    end
  end

  it 'does not guess from descriptions' do
    Dir.mktmpdir do |directory|
      record = semantic_record('revenue', 'Revenue').merge('description' => 'recognized income')
      registry = described_class.new(paths: write_registry(directory, metrics: [record]))

      expect { registry.resolve('recognized income', :metric) }
        .to raise_error(ZuQL::UnknownConceptError)
    end
  end

  it 'resolves the reviewed MVP business-term aliases' do
    {
      'unpaid invoice balance' => [:metric, 'invoice_balance'],
      'payments total' => [:metric, 'payment_amount'],
      'customer account' => [:dimension, 'account'],
      'rate plan charge' => [:dimension, 'charge'],
      'catalog product' => [:dimension, 'product'],
      'currency code' => [:dimension, 'currency']
    }.each do |concept, (kind, id)|
      expect(registry.resolve(concept, kind)).to include(id: id, confidence: 0.9)
    end
  end

  it 'resolves qualified fields and reports their owning object' do
    expect(registry.resolve('account.name', :field)).to include(
      id: 'account.name', object_id: 'account', confidence: 1.0
    )
  end

  it 'fails closed for unknown concepts' do
    expect { registry.resolve('bookings', :metric) }
      .to raise_error(ZuQL::UnknownConceptError) { |error| expect(error.details).to include(kind: :metric) }
  end

  it 'fails closed for ambiguous unqualified fields' do
    expect { registry.resolve('name', :field) }
      .to raise_error(ZuQL::AmbiguousConceptError) do |error|
        expect(error.details.fetch(:candidates)).to include('account.name', 'subscription.name')
      end
  end

  it 'exposes immutable planner metadata by canonical identifier' do
    expect(registry.metric('current_mrr')).to include(
      id: 'current_mrr', field: 'rate_plan_charge.mrr',
      native_grain: 'rate_plan_charge', aggregation: 'sum'
    )
    expect(registry.dimension('account')).to include(id: 'account', field: 'account.name')
    expect(registry.object('subscription')).to include(id: 'subscription', default_grain: 'subscription')
    expect(registry.metric('current_mrr')).to be_frozen
  end

  def semantic_record(id, display_name, aliases: [])
    {
      'id' => id, 'display_name' => display_name, 'field' => 'account.id',
      'native_grain' => 'account', 'aggregation' => 'sum', 'aliases' => aliases,
      'warnings' => []
    }
  end

  def write_registry(directory, metrics:) # rubocop:disable Metrics/MethodLength
    paths = {
      metrics: File.join(directory, 'metrics.yml'), dimensions: File.join(directory, 'dimensions.yml'),
      objects: File.join(directory, 'objects.yml')
    }
    File.write(paths.fetch(:metrics), YAML.dump('metrics' => metrics))
    File.write(paths.fetch(:dimensions), YAML.dump('dimensions' => []))
    File.write(paths.fetch(:objects), YAML.dump('objects' => [
                                                  {
                                                    'id' => 'account', 'display_name' => 'Account',
                                                    'fields' => [
                                                      { 'id' => 'id', 'display_name' => 'ID', 'type' => 'string' }
                                                    ]
                                                  }
                                                ]))
    paths
  end
end
