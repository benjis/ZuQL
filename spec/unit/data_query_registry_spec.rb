# frozen_string_literal: true

require 'zuql'

RSpec.describe ZuQL::DataQueryRegistry do
  subject(:registry) { described_class.new }

  it 'maps canonical objects to safe Data Query physical names' do
    expect(registry.object('rate_plan_charge')).to include(
      id: 'rate_plan_charge', physical_name: 'RatePlanCharge', verified: false
    )
    expect(registry.object('rate_plan_charge').fetch(:warnings)).to include(/convention-derived/i)
    expect(registry.object('rate_plan_charge')).to be_frozen
  end

  it 'uses verified user-observed Data Query object mappings' do
    expect(registry.object('billing_run')).to include(
      id: 'billing_run', physical_name: 'BillingRun', verified: true, warnings: []
    )
  end

  it 'maps canonical fields through their curated display names' do
    expect(registry.field('account.account_number')).to include(
      id: 'account.account_number', object_id: 'account', physical_name: 'AccountNumber'
    )
    expect(registry.field('account.id')).to include(physical_name: 'ID')
  end

  it 'returns metric aggregation metadata' do
    expect(registry.metric('current_mrr')).to include(
      id: 'current_mrr', field: 'rate_plan_charge.mrr', aggregation: 'sum'
    )
  end

  it 'returns approved relationship endpoints and join fields' do
    expect(registry.relationship('account.subscription')).to include(
      id: 'account.subscription', from_object: 'account', to_object: 'subscription',
      from_field: 'id', to_field: 'account_id'
    )
  end

  it 'fails closed for unknown metadata and unapproved relationships' do
    expect { registry.object('made_up') }
      .to raise_error(ZuQL::CompilationError) { |error| expect(error.details).to include(kind: 'object') }
    expect { registry.field('account.made_up') }.to raise_error(ZuQL::CompilationError)
    expect { registry.metric('made_up') }.to raise_error(ZuQL::CompilationError)
    expect { registry.relationship('payment.payment_part') }
      .to raise_error(ZuQL::CompilationError) { |error| expect(error.details).to include(kind: 'relationship') }
  end

  it 'wraps malformed YAML and incomplete mappings in typed compilation errors' do
    fixture_root = File.expand_path('../fixtures/registry', __dir__)
    malformed_paths = described_class::DEFAULT_PATHS.merge(
      data_sources: File.join(fixture_root, 'malformed_data_sources.yml')
    )
    missing_paths = described_class::DEFAULT_PATHS.merge(
      data_sources: File.join(fixture_root, 'missing_mapping_data_sources.yml')
    )

    expect { described_class.new(paths: malformed_paths) }
      .to raise_error(ZuQL::CompilationError) { |error| expect(error.details).to include(kind: 'registry') }
    incomplete = described_class.new(paths: missing_paths)
    expect { incomplete.object('account') }
      .to raise_error(ZuQL::CompilationError) { |error| expect(error.details).to include(kind: 'object') }
  end
end
