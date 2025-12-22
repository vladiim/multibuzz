# frozen_string_literal: true

module Shopify
  module Handlers
    class CustomerCreated < Base
      def call
        return { success: false, error: "Visitor not found" } unless visitor

        link_visitor_to_identity
        { success: true, identity_id: identity.prefix_id }
      end

      private

      def identity
        @identity ||= account.identities.find_or_create_by!(external_id: customer_id.to_s) do |idt|
          idt.traits = identity_traits
          idt.first_identified_at = Time.current
          idt.last_identified_at = Time.current
        end
      end

      def link_visitor_to_identity
        visitor.update!(identity: identity)
      end

      def identity_traits
        {
          email: customer_email,
          first_name: first_name,
          last_name: last_name
        }.compact
      end

      def customer_id
        payload[:id]
      end

      def customer_email
        payload[:email]
      end

      def first_name
        payload[:first_name]
      end

      def last_name
        payload[:last_name]
      end
    end
  end
end
