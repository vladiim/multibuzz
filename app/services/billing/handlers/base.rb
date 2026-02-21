# frozen_string_literal: true

module Billing
  module Handlers
    class Base < ApplicationService
      def initialize(event_data)
        @event_data = event_data
      end

      private

      attr_reader :event_data

      def run
        return account_not_found_error unless account

        handle_event
        success_result(account: account)
      end

      def handle_event
        raise NotImplementedError, "Subclasses must implement #handle_event"
      end

      def account
        @account ||= Account.find_by(stripe_customer_id: customer_id)
      end

      def customer_id
        event_object[:customer]
      end

      def event_object
        event_data.dig(:data, :object) || {}
      end

      def account_not_found_error
        error_result([ "Account not found for customer: #{customer_id}" ])
      end
    end
  end
end
