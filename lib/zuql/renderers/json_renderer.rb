# frozen_string_literal: true

module ZuQL
  module Renderers
    class JsonRenderer
      def render(result)
        result = ResultInput.validate!(result)
        "#{JSON.pretty_generate(result.to_h)}\n".freeze
      end
    end
  end
end
