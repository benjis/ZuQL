# frozen_string_literal: true

require 'zuql'

RSpec.describe ZuQL::SemanticResolver do
  subject(:resolver) { described_class.new }

  def query_spec(overrides = {})
    ZuQL::Contracts::QuerySpec.from_h(
      {
        intent: 'aggregate', requested_entities: [], requested_fields: [], filters: [],
        metrics: [], dimensions: [], group_by: [], order_by: [], limit: 1000,
        backend_preference: 'auto'
      }.merge(overrides)
    )
  end

  it 'resolves MRR by account and collects semantic warnings' do
    resolved = resolver.resolve(query_spec(metrics: ['MRR'], dimensions: ['Account']))

    expect(resolved.resolutions.map(&:resolved_to)).to eq(%w[current_mrr account])
    expect(resolved.warnings).to include(/not recognized revenue/i)
    expect(resolved).to be_frozen
  end

  it 'resolves subscription count grouped by status' do
    resolved = resolver.resolve(
      query_spec(metrics: ['Subscription Count'], group_by: ['Subscription Status'])
    )

    expect(resolved.resolutions.map(&:resolved_to)).to eq(%w[subscription_count subscription_status])
  end

  it 'resolves payment amount grouped by payment date' do
    resolved = resolver.resolve(query_spec(metrics: ['Payment Amount'], group_by: ['Payment Date']))

    expect(resolved.resolutions.map(&:resolved_to)).to eq(%w[payment_amount payment_date])
  end

  it 'resolves entities, requested fields, and filter dimensions' do
    resolved = resolver.resolve(
      query_spec(
        requested_entities: ['Subscription'],
        requested_fields: [{ concept: 'subscription.name' }],
        filters: [{ concept: 'Subscription Status', operator: 'equals', value: 'Active' }]
      )
    )

    expect(resolved.resolutions.map(&:kind)).to eq(%w[object field dimension])
    expect(resolved.resolutions.map(&:resolved_to)).to eq(%w[subscription subscription.name subscription_status])
  end

  it 'deduplicates the same supplied concept in stable order' do
    resolved = resolver.resolve(query_spec(dimensions: ['Account'], group_by: ['Account']))

    expect(resolved.resolutions.map(&:resolved_to)).to eq(['account'])
  end

  it 'fails for unknown and ambiguous concepts' do
    expect { resolver.resolve(query_spec(metrics: ['Bookings'])) }.to raise_error(ZuQL::UnknownConceptError)
    expect { resolver.resolve(query_spec(requested_fields: [{ concept: 'name' }])) }
      .to raise_error(ZuQL::AmbiguousConceptError)
  end

  it 'fails when implied objects require an unapproved relationship' do
    spec = query_spec(metrics: ['Payment Amount'], requested_entities: ['Payment Run'])

    expect { resolver.resolve(spec) }.to raise_error(ZuQL::UnreachableObjectsError)
  end
end
