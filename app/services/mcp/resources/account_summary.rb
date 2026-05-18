# frozen_string_literal: true

module Mcp
  module Resources
    # One-shot account snapshot exposed as the mbuzz://account/summary MCP
    # resource. Lets an agent prime itself in a single read instead of probing
    # with tool calls — account name, data date range, connected ad platforms,
    # default attribution model, and the funnels it can filter by.
    class AccountSummary
      URI = "mbuzz://account/summary"
      MIME_TYPE = "application/json"

      def self.resource
        ::MCP::Resource.new(
          uri: URI,
          name: "account-summary",
          title: "Account summary",
          description: "A snapshot of the mbuzz account: name, earliest event date, connected ad " \
                       "platforms, default attribution model, available funnels, and currencies. " \
                       "Read this first to ground answers before calling the data tools.",
          mime_type: MIME_TYPE
        )
      end

      def initialize(account:, api_key:)
        @account = account
        @api_key = api_key
      end

      def to_h
        {
          account_name: account.name,
          environment: api_key.test? ? "test" : "live",
          first_event_at: first_event_at,
          selected_sdk: account.selected_sdk,
          active_ad_platforms: active_ad_platforms,
          default_attribution_model: default_attribution_model,
          available_funnels: available_funnels,
          currencies: currencies
        }
      end

      private

      attr_reader :account, :api_key

      def first_event_at
        account.events.minimum(:occurred_at)&.to_date&.to_s
      end

      def active_ad_platforms
        account.ad_platform_connections.where.not(status: :disconnected).map(&:platform).uniq.sort
      end

      def default_attribution_model
        account.attribution_models.find_by(is_default: true)&.name
      end

      def available_funnels
        (account.events.where.not(funnel: nil).distinct.pluck(:funnel) +
          account.conversions.where.not(funnel: nil).distinct.pluck(:funnel)).uniq.sort
      end

      def currencies
        account.conversions.where.not(currency: nil).distinct.pluck(:currency).sort
      end
    end
  end
end
