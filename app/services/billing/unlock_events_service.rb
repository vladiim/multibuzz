# frozen_string_literal: true

module Billing
  class UnlockEventsService < ApplicationService
    def initialize(account)
      @account = account
    end

    private

    attr_reader :account

    def run
      return no_locked_events_result if locked_events.none?

      capture_locked_period
      perform_unlock
      build_result
    end

    def no_locked_events_result
      success_result(unlocked_count: 0)
    end

    def capture_locked_period
      @earliest_locked_at = locked_events.minimum(:occurred_at)
      @latest_locked_at = locked_events.maximum(:occurred_at)
    end

    def perform_unlock
      ActiveRecord::Base.transaction do
        unlock_events
        restore_account_status
        enqueue_reattribution_jobs
      end
    end

    def build_result
      success_result(
        unlocked_count: unlocked_count,
        earliest_unlocked: @earliest_locked_at,
        latest_unlocked: @latest_locked_at,
        conversions_reattributed: conversions_in_locked_period.count
      )
    end

    # --- Unlock Operations ---

    def unlock_events
      @unlocked_count = locked_events.update_all(locked: false)
    end

    def restore_account_status
      return unless account.billing_past_due?

      account.restore_from_past_due!
    end

    def enqueue_reattribution_jobs
      conversions_in_locked_period.find_each do |conversion|
        Conversions::ReattributionJob.perform_later(conversion.id)
      end
    end

    # --- Queries ---

    def locked_events
      @locked_events ||= account.events.where(locked: true)
    end

    def conversions_in_locked_period
      return Conversion.none unless locked_period?

      @conversions_in_locked_period ||= account.conversions
        .where(converted_at: @earliest_locked_at..@latest_locked_at)
    end

    def locked_period?
      @earliest_locked_at.present? && @latest_locked_at.present?
    end

    def unlocked_count
      @unlocked_count || 0
    end
  end
end
