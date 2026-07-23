# frozen_string_literal: true

require 'zuql'

RSpec.describe ZuQL::GrainValidator do
  subject(:validator) { described_class.new(query_spec, resolutions, ZuQL::SemanticRegistry.new) }

  let(:query_spec) do
    ZuQL::Contracts::QuerySpec.from_h(
      intent: 'aggregate', requested_entities: [], requested_fields: [], filters: [],
      metrics: ['MRR'], dimensions: [], group_by: [], order_by: [], limit: 1000,
      backend_preference: 'auto'
    )
  end
  let(:resolutions) do
    [
      ZuQL::Contracts::Resolution.from_h(
        input: 'MRR', resolved_to: 'current_mrr', kind: 'metric', confidence: 1.0
      )
    ]
  end

  {
    one_to_many: { forward: true, inverse: false },
    many_to_one: { forward: false, inverse: true },
    many_to_many: { forward: true, inverse: true },
    one_to_one: { forward: false, inverse: false }
  }.each do |cardinality, directions|
    directions.each do |direction, risky|
      it "treats #{direction} #{cardinality} traversal as #{risky ? 'unsafe' : 'safe'}" do
        from, to = direction == :forward ? %w[parent child] : %w[child parent]
        edge = {
          id: 'parent.child', from_object: 'parent', to_object: 'child',
          cardinality: cardinality.to_s, traverse_from: from, traverse_to: to
        }

        if risky
          expect { validator.validate_fanout!([edge]) }.to raise_error(ZuQL::FanoutRiskError)
        else
          expect { validator.validate_fanout!([edge]) }.not_to raise_error
        end
      end
    end
  end
end
