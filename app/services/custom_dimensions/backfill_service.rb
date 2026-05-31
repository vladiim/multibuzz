# frozen_string_literal: true

module CustomDimensions
  # Re-materialises every connection's spend rows for an account after its
  # dimensions or rules change. Account-scoped; delegates per-connection work to
  # ConnectionBackfill. No ad-platform API calls — recomputed from stored rows.
  class BackfillService < ApplicationService
    def initialize(account)
      @account = account
    end

    private

    attr_reader :account

    def run
      account.ad_platform_connections.each { |connection| ConnectionBackfill.new(connection).call }
      success_result
    end
  end
end
