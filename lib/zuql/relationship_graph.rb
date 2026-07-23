# frozen_string_literal: true

require 'yaml'

module ZuQL
  # Validates that objects share a path made only of approved relationships.
  class RelationshipGraph # rubocop:disable Metrics/ClassLength
    DEFAULT_PATH = File.expand_path('../../data/canonical/relationships.yml', __dir__)

    def initialize(path: DEFAULT_PATH, relationships: nil)
      records = relationships || YAML.safe_load_file(path).fetch('relationships')
      @adjacency = build_adjacency(records)
    end

    def connect!(object_ids)
      required = object_ids.uniq
      return self if required.length < 2

      reachable = reachable_from(required.first)
      unreachable = required.reject { |object_id| reachable.include?(object_id) }
      raise UnreachableObjectsError, unreachable unless unreachable.empty?

      self
    end

    def paths(root, targets)
      selected = targets.uniq.sort.each_with_object({}) do |target, edges|
        best_path(root, target).each { |edge| edges[edge.fetch(:id)] = edge }
      end
      ordered_edges(root, selected)
    end

    private

    def build_adjacency(relationships)
      graph = Hash.new { |adjacency, object| adjacency[object] = [] }
      relationships.each do |relationship|
        add_relationship(graph, relationship) if reviewed?(relationship)
      end
      graph
    end

    def reviewed?(relationship)
      relationship['approved_for_planning'] == true && relationship.fetch('confidence', 'candidate') == 'reviewed'
    end

    def add_relationship(graph, relationship)
      edge = relationship_edge(relationship)
      graph[edge.fetch(:from_object)] << [edge.fetch(:to_object), edge].freeze
      graph[edge.fetch(:to_object)] << [edge.fetch(:from_object), edge].freeze
    end

    def relationship_edge(relationship)
      {
        id: relationship.fetch('id'), from_object: relationship.fetch('from_object'),
        to_object: relationship.fetch('to_object'), cardinality: relationship.fetch('cardinality'),
        fanout_risk: relationship.fetch('fanout_risk', nil)
      }.freeze
    end

    def reachable_from(start)
      visited = { start => true }
      queue = [start]
      until queue.empty?
        sorted_neighbors(queue.shift).map(&:first).each do |neighbor|
          next if visited.key?(neighbor)

          visited[neighbor] = true
          queue << neighbor
        end
      end
      visited.keys
    end

    def best_path(root, target) # rubocop:disable Metrics/AbcSize
      return [] if root == target

      candidates = shortest_paths(root, target)
      raise UnreachableObjectsError, [target] if candidates.empty?

      ranked = candidates.group_by { |path| path_cost(path) }
      best = ranked.fetch(ranked.keys.min)
      return best.first if best.length == 1

      raise AmbiguousJoinPathError.new(
        root, target, candidates: best.map { |path| path.map { |edge| edge.fetch(:id) } }.sort
      )
    end

    def shortest_paths(root, target) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      best_distance = nil
      candidates = []
      queue = [[root, []]]
      until queue.empty?
        current, path = queue.shift
        next if best_distance && path.length >= best_distance

        sorted_neighbors(current).each do |neighbor, relationship|
          visited_objects = [root] + path.map { |edge| edge.fetch(:traverse_to) }
          next if visited_objects.include?(neighbor)

          edge = relationship.merge(traverse_from: current, traverse_to: neighbor).freeze
          candidate = path + [edge]
          if neighbor == target
            best_distance ||= candidate.length
            candidates << candidate if candidate.length == best_distance
          else
            queue << [neighbor, candidate]
          end
        end
      end
      candidates
    end

    def path_cost(path)
      [path.length, path.sum { |edge| fanout_cost(edge) }]
    end

    def fanout_cost(edge)
      explicit = { 'none' => 0, 'low' => 1, 'medium' => 2, 'high' => 3 }[edge.fetch(:fanout_risk)]
      return explicit unless explicit.nil?

      forward = edge.fetch(:traverse_from) == edge.fetch(:from_object)
      duplicates = edge.fetch(:cardinality) == 'many_to_many' ||
                   (edge.fetch(:cardinality) == 'one_to_many' && forward) ||
                   (edge.fetch(:cardinality) == 'many_to_one' && !forward)
      duplicates ? 3 : 0
    end

    def ordered_edges(root, selected) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
      result = []
      visited = { root => true }
      until result.length == selected.length
        candidates = selected.values.select do |edge|
          visited.key?(edge.fetch(:traverse_from)) && !visited.key?(edge.fetch(:traverse_to))
        end
        raise UnreachableObjectsError, selected.keys if candidates.empty?

        candidates.sort_by { |edge| [edge.fetch(:id), edge.fetch(:traverse_to)] }.each do |edge|
          next if visited.key?(edge.fetch(:traverse_to))

          result << edge
          visited[edge.fetch(:traverse_to)] = true
        end
      end
      result.freeze
    end

    def sorted_neighbors(object)
      @adjacency.fetch(object, []).sort_by { |neighbor, relationship| [relationship.fetch(:id), neighbor] }
    end
  end
end
