# frozen_string_literal: true

require 'yaml'

module ZuQL
  module Providers
    class FixtureProvider
      DEFAULT_PATH = File.expand_path('../../../data/fixtures/query_interpretations.yml', __dir__)

      def self.from_yaml(path = DEFAULT_PATH)
        document = YAML.safe_load_file(
          path, permitted_classes: [], permitted_symbols: [], aliases: false
        )
        new(fixtures: fixtures_from(document))
      rescue InterpretationProviderError
        raise
      rescue StandardError => e
        raise InterpretationProviderError.new(
          'Fixture data is invalid', details: { reason: 'unreadable_fixture_data' }
        ), cause: e
      end

      def self.fixtures_from(document)
        validate_document!(document)

        document['questions'].each_with_object({}) { |entry, fixtures| add_fixture!(fixtures, entry) }
      end
      private_class_method :fixtures_from

      def self.validate_document!(document)
        valid = document.instance_of?(Hash) && document['version'] == 1
        return if valid && document['questions'].instance_of?(Array)

        raise InterpretationProviderError.new(
          'Fixture data is invalid', details: { reason: 'invalid_document_shape' }
        )
      end
      private_class_method :validate_document!

      def self.add_fixture!(fixtures, entry)
        question, response = fixture_entry(entry)
        if fixtures.key?(question)
          raise InterpretationProviderError.new(
            'Fixture data is invalid', details: { reason: 'duplicate_question' }
          )
        end
        fixtures[question] = response
      end
      private_class_method :add_fixture!

      def self.fixture_entry(entry)
        question = entry['question'] if entry.instance_of?(Hash)
        response = entry['response'] if entry.instance_of?(Hash)
        valid_question = question.instance_of?(String) && !question.strip.empty?
        return [question, response] if valid_question && response.instance_of?(Hash)

        raise InterpretationProviderError.new(
          'Fixture data is invalid', details: { reason: 'invalid_question_entry' }
        )
      end
      private_class_method :fixture_entry

      def initialize(fixtures:)
        validate_fixture_map!(fixtures)
        @responses = serialize_fixtures(fixtures).freeze
        @questions = @responses.keys.map { |question| question.dup.freeze }.freeze
      rescue JSON::GeneratorError, TypeError => e
        raise invalid_response_error, cause: e
      end

      def complete(question:, **_context)
        response = @responses[question]
        return response if response

        raise InterpretationProviderError.new(
          'No fixture exists for this question', details: { reason: 'unknown_question' }
        )
      end

      attr_reader :questions

      private

      def validate_fixture_map!(fixtures)
        return if fixtures.instance_of?(Hash)

        raise InterpretationProviderError.new(
          'Fixture data is invalid', details: { reason: 'invalid_fixture_map' }
        )
      end

      def serialize_fixtures(fixtures)
        fixtures.to_h do |question, response|
          validate_fixture!(question, response)
          [question.dup.freeze, JSON.generate(response).freeze]
        end
      end

      def invalid_response_error
        InterpretationProviderError.new(
          'Fixture data is invalid', details: { reason: 'invalid_fixture_response' }
        )
      end

      def validate_fixture!(question, response)
        valid_question = question.instance_of?(String) && !question.strip.empty?
        return if valid_question && response.instance_of?(Hash)

        raise InterpretationProviderError.new(
          'Fixture data is invalid', details: { reason: 'invalid_fixture_entry' }
        )
      end
    end
  end
end
