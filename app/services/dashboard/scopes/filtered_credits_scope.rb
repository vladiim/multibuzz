# frozen_string_literal: true

module Dashboard
  module Scopes
    class FilteredCreditsScope < CreditsScope
      def initialize(account:, models:, date_range:, channels: Channels::ALL, test_mode: false, conversion_filters: [])
        super(account: account, models: models, date_range: date_range, channels: channels, test_mode: test_mode)
        @conversion_filters = conversion_filters || []
      end

      def call
        super.then { |scope| apply_conversion_filters(scope) }
      end

      private

      attr_reader :conversion_filters

      def apply_conversion_filters(scope)
        conversion_filters.reduce(scope) { |s, filter| FilterApplicator.new(filter).call(s) }
      end

      class FilterApplicator
        def initialize(filter)
          @filter = filter
        end

        def call(scope)
          operator_class ? operator_class.new(field: field, values: values).call(scope) : scope
        end

        private

        attr_reader :filter

        def field
          @field ||= filter[:field]
        end

        def values
          @values ||= filter[:values]
        end

        def operator_class
          @operator_class ||= "Dashboard::Scopes::Operators::#{operator_name}".safe_constantize
        end

        def operator_name
          @operator_name ||= filter[:operator].to_s.camelize
        end
      end
    end
  end
end
