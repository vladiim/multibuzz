# frozen_string_literal: true

module Dashboard
  module Scopes
    class FilteredAcquisitionsScope
      def initialize(account:, date_range:, channels:, attribution_model:,
                     conversion_filters: [], test_mode: false)
        @account = account
        @date_range = date_range
        @channels = channels
        @attribution_model = attribution_model
        @conversion_filters = conversion_filters || []
        @test_mode = test_mode
      end

      def call
        base_scope
          .then { |scope| apply_date_range(scope) }
          .then { |scope| apply_channels(scope) }
          .then { |scope| apply_conversion_filters(scope) }
      end

      private

      attr_reader :account, :date_range, :channels, :attribution_model,
                  :conversion_filters, :test_mode

      def base_scope
        account.conversions
          .where(is_acquisition: true)
          .then { |scope| test_mode ? scope.test_data : scope.production }
      end

      def apply_date_range(scope)
        scope.where(converted_at: date_range.to_range)
      end

      def apply_channels(scope)
        return scope if channels == Channels::ALL

        scope.where(id: acquisition_ids_for_channels)
      end

      def acquisition_ids_for_channels
        AttributionCredit
          .where(attribution_model: attribution_model)
          .where(channel: channels)
          .select(:conversion_id)
      end

      def apply_conversion_filters(scope)
        conversion_filters.reduce(scope) { |s, filter| FilterApplicator.new(filter).call(s) }
      end

      # Reuses existing operators with table_name: nil for direct conversion queries
      class FilterApplicator
        def initialize(filter)
          @filter = filter
        end

        def call(scope)
          operator_class ? operator_class.new(field: field, values: values, table_name: nil).call(scope) : scope
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
