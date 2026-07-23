# frozen_string_literal: true

require 'zuql'

RSpec.describe ZuQL::PlanProjection do
  it 'makes colliding selection aliases unique and deterministic' do
    query_spec = ZuQL::Contracts::QuerySpec.from_h(
      intent: 'detail_export', requested_entities: [],
      requested_fields: [{ concept: 'first' }, { concept: 'second' }], filters: [],
      metrics: [], dimensions: [], group_by: [], order_by: [], limit: 1000,
      backend_preference: 'auto'
    )
    resolutions = [
      ZuQL::Contracts::Resolution.from_h(
        input: 'first', resolved_to: 'a.b_c', kind: 'field', confidence: 1.0
      ),
      ZuQL::Contracts::Resolution.from_h(
        input: 'second', resolved_to: 'a_b.c', kind: 'field', confidence: 1.0
      )
    ]

    projection = described_class.new(query_spec, resolutions, ZuQL::SemanticRegistry.new)

    expect(projection.selections.map { |selection| selection.fetch(:alias) }).to eq(%w[a_b_c a_b_c_2])
  end
end
