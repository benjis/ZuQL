# frozen_string_literal: true

module ZuQL
  module Renderers
    class MarkdownRenderer
      MARKDOWN_PUNCTUATION = %r{([!"#$%'()*+,\-./:<=>?@\[\\\]^_`{|}~])}

      def render(result)
        result = ResultInput.validate!(result)
        lines = heading_lines(result) + explanation_lines(result) + sql_lines(result)
        "#{lines.join("\n")}\n".freeze
      end

      private

      def bullets(values, empty: nil)
        values = [empty] if values.empty? && empty
        values.map { |value| "- #{escape(value)}" }
      end

      def heading_lines(result)
        query_spec = JSON.pretty_generate(result.query_spec.to_h)
        fence = content_fence(query_spec)
        ['# ZuQL Query Explanation', '', '## Question', escape(result.question), '',
         '## Summary', escape(result.explanation.summary), '',
         '## QuerySpec', "#{fence}json", query_spec, fence, '']
      end

      def explanation_lines(result) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        explanation = result.explanation
        ['## Interpretation', escape(explanation.interpretation), '',
         '## Resolutions', *bullets(explanation.resolutions), '',
         '## Filters', *bullets(explanation.filters), '', '## Metrics', *bullets(explanation.metrics), '',
         '## Root', escape(explanation.root), '', '## Join path', *bullets(explanation.joins), '',
         '## Inserted bridges', *bullets(explanation.inserted_bridges), '',
         '## Grain', escape(explanation.grain), '', '## Grouping', escape(explanation.grouping), '',
         '## Limit', result.plan.limit.to_s, '',
         '## Backend', escape(explanation.backend), '', '## Assumptions', *bullets(explanation.assumptions), '',
         '## Public canonical model limitation', escape(explanation.limitation), '',
         '## Mapping status', escape(explanation.mapping_status), '',
         '## Warnings', *bullets(result.warnings, empty: 'None'), '']
      end

      def sql_lines(result)
        sql = result.compiled_query.sql
        fence = sql_fence(sql)
        ['## SQL', "#{fence}sql", sql, fence]
      end

      def escape(value)
        encoded = value.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
        escaped = encoded.gsub(MARKDOWN_PUNCTUATION) { |match| "\\#{match}" }
        escaped.gsub(/\r\n?|\n/, '\\n').gsub("\t", '\\t')
      end

      def sql_fence(sql)
        content_fence(sql)
      end

      def content_fence(content)
        longest = content.scan(/`+/).map(&:length).max.to_i
        '`' * [3, longest + 1].max
      end
    end
  end
end
