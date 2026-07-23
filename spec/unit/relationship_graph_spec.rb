# frozen_string_literal: true

require 'zuql'

RSpec.describe ZuQL::RelationshipGraph do
  subject(:graph) { described_class.new }

  it 'connects objects through approved relationships in either direction' do
    expect(graph.connect!(%w[account rate_plan_charge])).to equal(graph)
    expect(graph.connect!(%w[rate_plan_charge account])).to equal(graph)
  end

  it 'does not traverse relationships that are not approved for planning' do
    expect { graph.connect!(%w[payment payment_run]) }
      .to raise_error(ZuQL::UnreachableObjectsError) do |error|
        expect(error.details).to eq(object_ids: ['payment_run'])
      end
  end

  it 'accepts zero or one required object without a join' do
    expect(graph.connect!([])).to equal(graph)
    expect(graph.connect!(['payment_run'])).to equal(graph)
  end

  it 'returns deterministic shortest paths with bridge objects and traversal direction' do
    path = graph.paths('account', %w[rate_plan_charge invoice_item]).map do |edge|
      edge.values_at(:id, :traverse_from, :traverse_to)
    end

    expect(path).to eq(
      [
        %w[account.invoice account invoice],
        %w[account.subscription account subscription],
        %w[invoice.invoice_item invoice invoice_item],
        %w[subscription.rate_plan subscription rate_plan],
        %w[rate_plan.rate_plan_charge rate_plan rate_plan_charge]
      ]
    )
  end

  it 'orients a discovered path from the selected root' do
    expect(graph.paths('rate_plan_charge', ['account']).map do |edge|
      [edge.fetch(:traverse_from), edge.fetch(:traverse_to)]
    end).to eq(
      [%w[rate_plan_charge rate_plan], %w[rate_plan subscription], %w[subscription account]]
    )
  end

  it 'traverses every reviewed relationship in both directions' do
    relationships = YAML.safe_load_file(ZuQL::RelationshipGraph::DEFAULT_PATH)
                        .fetch('relationships')
                        .select { |relationship| relationship['approved_for_planning'] == true }

    relationships.each do |relationship|
      from = relationship.fetch('from_object')
      to = relationship.fetch('to_object')
      id = relationship.fetch('id')
      expect(graph.paths(from, [to]).map { |edge| edge.fetch(:id) }).to eq([id])
      expect(graph.paths(to, [from]).map { |edge| edge.fetch(:id) }).to eq([id])
    end
  end

  it 'chooses the lower fan-out-risk path when reviewed paths have equal length' do
    graph = described_class.new(relationships: [
                                  relationship('root.risky', 'root', 'risky', 'one_to_many'),
                                  relationship('risky.target', 'risky', 'target', 'many_to_one'),
                                  relationship('root.safe', 'root', 'safe', 'many_to_one'),
                                  relationship('safe.target', 'safe', 'target', 'many_to_one')
                                ])

    expect(graph.paths('root', ['target']).map { |edge| edge.fetch(:id) })
      .to eq(%w[root.safe safe.target])
  end

  it 'rejects equally safe reviewed paths instead of silently using relationship IDs' do
    graph = described_class.new(relationships: [
                                  relationship('root.left', 'root', 'left', 'many_to_one'),
                                  relationship('left.target', 'left', 'target', 'many_to_one'),
                                  relationship('root.right', 'root', 'right', 'many_to_one'),
                                  relationship('right.target', 'right', 'target', 'many_to_one')
                                ])

    expect { graph.paths('root', ['target']) }
      .to raise_error(ZuQL::AmbiguousJoinPathError) do |error|
        expect(error.details.fetch(:candidates)).to eq(
          [%w[root.left left.target], %w[root.right right.target]]
        )
      end
  end

  it 'never plans through an unreviewed relationship' do
    candidate = relationship('root.target', 'root', 'target', 'one_to_one')
                .merge('confidence' => 'candidate')
    graph = described_class.new(relationships: [candidate])

    expect { graph.paths('root', ['target']) }.to raise_error(ZuQL::UnreachableObjectsError)
  end

  def relationship(id, from, to, cardinality)
    {
      'id' => id, 'from_object' => from, 'to_object' => to,
      'cardinality' => cardinality, 'approved_for_planning' => true,
      'confidence' => 'reviewed'
    }
  end
end
