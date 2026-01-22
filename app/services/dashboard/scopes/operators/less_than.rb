# frozen_string_literal: true

module Dashboard
  module Scopes
    module Operators
      class LessThan < Base
        private

        def apply_to_column(scope)
          scope.where("#{column_path(field)} < ?", numeric_value)
        end

        def apply_to_property(scope)
          scope.where("(#{property_path})::numeric < ?", numeric_value)
        end

        def numeric_value
          @numeric_value ||= values.first.to_f
        end
      end
    end
  end
end
