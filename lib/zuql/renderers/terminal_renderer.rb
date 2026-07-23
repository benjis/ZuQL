# frozen_string_literal: true

module ZuQL
  module Renderers
    class TerminalRenderer
      def render(result)
        result = ResultInput.validate!(result)
        explanation = result.explanation
        lines = heading_lines(result, explanation) + explanation_lines(result, explanation) + sql_lines(result)
        "#{lines.join("\n")}\n".freeze
      end

      private

      def list(values, empty: 'None')
        values.empty? ? [empty] : values
      end

      def heading_lines(result, explanation)
        ['Question', result.question, '', 'Explanation', '', 'Summary', explanation.summary, '',
         'QuerySpec', JSON.pretty_generate(result.query_spec.to_h), '']
      end

      def explanation_lines(result, explanation) # rubocop:disable Metrics/AbcSize
        ['Interpretation', explanation.interpretation, '', 'Resolutions', *list(explanation.resolutions), '',
         'Filters', *list(explanation.filters), '', 'Metrics', *list(explanation.metrics), '',
         'Root', explanation.root, '', 'Join path', *explanation.joins, '',
         'Inserted bridges', *explanation.inserted_bridges, '', 'Grain', explanation.grain, '',
         'Grouping', explanation.grouping, '', 'Limit', result.plan.limit.to_s, '',
         'Backend', explanation.backend, '', 'Assumptions', *explanation.assumptions, '',
         'Public canonical model limitation', explanation.limitation, '',
         'Mapping status', explanation.mapping_status, '', 'Warnings', *list(result.warnings, empty: 'None'), '']
      end

      def sql_lines(result)
        ['SQL', result.compiled_query.sql]
      end
    end
  end
end
