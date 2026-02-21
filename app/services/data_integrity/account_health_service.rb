# frozen_string_literal: true

module DataIntegrity
  class AccountHealthService
    def initialize(account)
      @account = account
    end

    def call
      Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
        latest_worst_status
      end
    end

    private

    attr_reader :account

    def latest_worst_status
      account.data_integrity_checks
        .where("created_at >= ?", 2.hours.ago)
        .order(Arel.sql("CASE status WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END"))
        .pick(:status) || "unknown"
    end

    def cache_key
      "data_integrity/health/#{account.id}"
    end
  end
end
