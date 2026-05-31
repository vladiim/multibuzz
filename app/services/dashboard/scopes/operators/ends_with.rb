# frozen_string_literal: true

module Dashboard
  module Scopes
    module Operators
      class EndsWith < Like
        def self.pattern(value)
          "#{WILDCARD}#{value}"
        end

        def self.matches?(candidate, value)
          candidate.to_s.downcase.end_with?(value.to_s.downcase)
        end
      end
    end
  end
end
