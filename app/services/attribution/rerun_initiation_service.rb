# frozen_string_literal: true

module Attribution
  class RerunInitiationService < ApplicationService
    def initialize(attribution_model:, confirm_overage: false)
      @attribution_model = attribution_model
      @confirm_overage = confirm_overage
    end

    private

    attr_reader :attribution_model, :confirm_overage

    def run
      return error_result(["No stale conversions to rerun"]) unless stale_count.positive?
      return overage_required_result unless can_proceed?

      create_and_enqueue_job
    end

    def stale_count
      @stale_count ||= attribution_model.stale_conversions_count
    end

    def overage_calculation
      @overage_calculation ||= account.calculate_rerun_overage(stale_count)
    end

    def requires_overage?
      overage_calculation[:overage].positive?
    end

    def can_proceed?
      return true unless requires_overage?

      confirm_overage && account.has_active_subscription?
    end

    def overage_required_result
      {
        success: false,
        requires_confirmation: true,
        overage: overage_calculation
      }
    end

    def create_and_enqueue_job
      job = create_rerun_job
      enqueue_processing(job)

      success_result(
        rerun_job: job,
        overage: overage_calculation
      )
    end

    def create_rerun_job
      RerunJob.create!(
        account: account,
        attribution_model: attribution_model,
        total_conversions: stale_count,
        from_version: current_credit_version,
        to_version: attribution_model.version,
        overage_blocks: overage_calculation[:blocks]
      )
    end

    def current_credit_version
      attribution_model
        .attribution_credits
        .maximum(:model_version) || 0
    end

    def enqueue_processing(job)
      Attribution::RerunProcessingJob.perform_later(job.id)
    end

    def account
      @account ||= attribution_model.account
    end
  end
end
