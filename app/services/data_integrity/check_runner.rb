# frozen_string_literal: true

module DataIntegrity
  class CheckRunner < ApplicationService
    CHECK_NAMES = %w[
      GhostSessionRate
      SessionInflation
      VisitorInflation
      SelfReferralRate
      AttributionMismatch
      SessionsPerConverter
      EventVolume
      FingerprintInstability
      MissingFingerprintRate
      ExtremeSessionVisitors
    ].freeze

    def initialize(account)
      @account = account
    end

    private

    attr_reader :account

    def run
      results = check_classes.map { |check_class| check_class.new(account).call }
      persist_results(results)
      success_result(results: results)
    end

    def check_classes
      CHECK_NAMES.map { |name| "DataIntegrity::Checks::#{name}".constantize }
    end

    def persist_results(results)
      results.each do |result|
        account.data_integrity_checks.create!(
          check_name: result[:check_name],
          status: result[:status],
          value: result[:value],
          warning_threshold: result[:warning_threshold],
          critical_threshold: result[:critical_threshold],
          details: result[:details]
        )
      end
    end
  end
end
