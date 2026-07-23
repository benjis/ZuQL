# frozen_string_literal: true

require 'json_schemer'

module ZuQL
  class QueryPrompt
    ROOT = File.expand_path('../..', __dir__)
    SUPPORTED_VERSIONS = %w[v1].freeze

    attr_reader :version, :response_schema

    def initialize(version: 'v1')
      raise ArgumentError, "Unsupported query prompt version: #{version}" unless SUPPORTED_VERSIONS.include?(version)

      @version = version.dup.freeze
      @template = File.read(File.join(ROOT, 'prompts', 'query_spec', "#{version}.txt")).freeze
      @response_schema = deep_freeze(
        JSON.parse(File.read(File.join(ROOT, 'schemas', 'model_query_intent.schema.json')))
      )
      @schemer = JSONSchemer.schema(@response_schema)
    end

    def render(question, metadata_context: {})
      format(
        @template, question_json: JSON.generate(question),
                   metadata_context_json: JSON.generate(metadata_context)
      ).dup.freeze
    end

    def valid_response?(payload)
      @schemer.valid?(payload)
    end

    private

    def deep_freeze(value)
      case value
      when Hash
        value.each do |key, item|
          deep_freeze(key)
          deep_freeze(item)
        end
      when Array
        value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end
  end
end
