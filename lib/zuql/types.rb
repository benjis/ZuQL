# frozen_string_literal: true

require 'dry-types'

module ZuQL
  module Types
    include Dry.Types()

    Identifier = Strict::String.constrained(format: /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)?\z/)
    NonEmptyString = Strict::String.constrained(min_size: 1)
    PositiveInteger = Strict::Integer.constrained(gt: 0)
    Confidence = Strict::Float.constrained(gteq: 0.0, lteq: 1.0)
    StringList = Strict::Array.of(Strict::String)
    JsonScalar = Strict::String | Strict::Integer | Strict::Float | Strict::Bool | Strict::Nil
    JsonFilterValue = JsonScalar | Strict::Array.of(JsonScalar)
  end
end
