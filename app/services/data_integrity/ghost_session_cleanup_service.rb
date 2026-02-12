# frozen_string_literal: true

module DataIntegrity
  class GhostSessionCleanupService < ApplicationService
    def initialize(account)
      @account = account
    end

    private

    attr_reader :account

    def run
      cleaned = affected_conversions.map { |conversion| clean_conversion(conversion) }.compact

      success_result(conversions_cleaned: cleaned.size)
    end

    def clean_conversion(conversion)
      delete_suspect_credits(conversion)
      recalculate_attribution(conversion)
      conversion
    end

    def delete_suspect_credits(conversion)
      conversion.attribution_credits
        .where(session_id: suspect_session_ids)
        .destroy_all
    end

    def recalculate_attribution(conversion)
      conversion.attribution_credits.destroy_all
      conversion.update_column(:journey_session_ids, nil)
      Conversions::AttributionCalculationService.new(conversion).call
    end

    def affected_conversions
      account.conversions
        .where.not(journey_session_ids: nil)
        .select { |c| (c.journey_session_ids & suspect_session_ids).any? }
    end

    def suspect_session_ids
      @suspect_session_ids ||= account.sessions.where(suspect: true).pluck(:id)
    end
  end
end
