# frozen_string_literal: true

module ZuQL
  # Runs the deterministic offline natural-language-to-SQL stages in a fixed order.
  class Pipeline
    DEPENDENCIES = {
      interpreter: :interpret, resolver: :resolve, planner: :plan,
      compiler: :compile, validator: :validate!, explainer: :explain
    }.freeze

    # The explicit collaborators are part of the public dependency-injection API.
    def initialize( # rubocop:disable Metrics/ParameterLists
      interpreter:, resolver: SemanticResolver.new, planner: QueryPlanner.new,
      compiler: DataQueryCompiler.new, validator: SqlSafetyValidator.new,
      explainer: QueryExplainer.new
    )
      dependencies = {
        interpreter: interpreter, resolver: resolver, planner: planner,
        compiler: compiler, validator: validator, explainer: explainer
      }
      validate_dependencies!(dependencies)
      dependencies.each { |name, dependency| instance_variable_set("@#{name}", dependency) }
    end

    def call(question)
      artifacts = trusted_artifacts(question)
      query_spec = artifacts.fetch(:query_spec)
      resolved_query = artifacts.fetch(:resolved_query)
      plan = artifacts.fetch(:plan)
      explanation = @explainer.explain(
        query_spec: query_spec, resolved_query: resolved_query, plan: plan,
        compiled_query: artifacts.fetch(:trusted_query)
      )
      build_result(question, artifacts, explanation)
    end

    private

    def trusted_artifacts(question)
      query_spec = @interpreter.interpret(question)
      resolved_query = @resolver.resolve(query_spec)
      plan = @planner.plan(resolved_query)
      compiled_query = @compiler.compile(plan)
      trusted_query = @validator.validate!(plan, compiled_query)
      { query_spec: query_spec, resolved_query: resolved_query, plan: plan, trusted_query: trusted_query }
    end

    def build_result(question, artifacts, explanation)
      Contracts::PipelineResult.from_h(
        question: question, query_spec: artifacts.fetch(:query_spec).to_h,
        resolutions: artifacts.fetch(:resolved_query).resolutions.map(&:to_h),
        plan: artifacts.fetch(:plan).to_h,
        compiled_query: artifacts.fetch(:trusted_query).to_h,
        warnings: warnings_for(artifacts),
        explanation: explanation.to_h
      )
    end

    def warnings_for(artifacts)
      resolved = artifacts.fetch(:resolved_query).warnings
      planned = artifacts.fetch(:plan).warnings
      trusted = artifacts.fetch(:trusted_query).warnings
      (resolved + planned + trusted).uniq
    end

    def validate_dependencies!(dependencies)
      DEPENDENCIES.each do |name, method|
        next if dependencies.fetch(name).respond_to?(method)

        raise ArgumentError, "#{name} must respond to ##{method}"
      end
    end
  end
end
