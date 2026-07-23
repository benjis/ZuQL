# frozen_string_literal: true

module ZuQL
  # Quotes compiler-controlled identifiers using Trino delimited syntax.
  class DataQueryIdentifier
    def render(value)
      name = value.to_s
      unless name.match?(/\A[A-Za-z][A-Za-z0-9_]*\z/)
        raise CompilationError.new(
          "Invalid Data Query identifier: #{value}", details: { identifier: value }
        )
      end

      %("#{name}")
    end
  end
end
