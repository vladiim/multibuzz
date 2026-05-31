# frozen_string_literal: true

module Dashboard
  module Scopes
    module Operators
      class StartsWith < Like
        def self.pattern(value)
          "#{value}#{WILDCARD}"
        end

        def self.matches?(candidate, value)
          candidate.to_s.downcase.start_with?(value.to_s.downcase)
        end
      end
    end
  end
end
