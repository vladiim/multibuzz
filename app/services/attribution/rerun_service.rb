# frozen_string_literal: true

module Attribution
  class RerunService < ApplicationService
    def initialize(rerun_job)
      @rerun_job = rerun_job
    end

    private

    attr_reader :rerun_job

    def run
      rerun_job.mark_processing!

      process_stale_conversions
      update_account_usage
      rerun_job.mark_completed!

      success_result(processed: rerun_job.processed_conversions)
    rescue StandardError => e
      rerun_job.mark_failed!(e.message)
      error_result([e.message])
    end

    def process_stale_conversions
      pending_conversions.find_each do |conversion|
        process_conversion(conversion)
        rerun_job.increment_processed!
      end
    end

    def pending_conversions
      account.conversions.where(id: pending_conversion_ids)
    end

    def pending_conversion_ids
      @pending_conversion_ids ||= (stale_conversion_ids + unattributed_conversion_ids).uniq
    end

    def stale_conversion_ids
      attribution_model
        .stale_credits
        .select(:conversion_id)
        .distinct
        .pluck(:conversion_id)
    end

    def unattributed_conversion_ids
      attribution_model
        .unattributed_conversions
        .pluck(:id)
    end

    def process_conversion(conversion)

      ActiveRecord::Base.transaction do
        delete_existing_credits(conversion)
        calculate_and_persist_credits(conversion)
      end
    end

    def delete_existing_credits(conversion)
      conversion.attribution_credits
        .where(attribution_model: attribution_model)
        .delete_all
    end

    def calculate_and_persist_credits(conversion)
      calculator_credits(conversion).each { |credit| persist_credit(conversion, credit) }
    end

    def calculator_credits(conversion)
      return [] unless identity_for(conversion)

      CrossDeviceCalculator.new(
        conversion: conversion,
        identity: identity_for(conversion),
        attribution_model: attribution_model,
        conversion_paths: precomputed_conversion_paths
      ).call
    end

    def precomputed_conversion_paths
      return nil unless attribution_model.markov_chain? || attribution_model.shapley_value?

      @precomputed_conversion_paths ||= Markov::ConversionPathsQuery.new(account).call
    end

    def identity_for(conversion)
      conversion.visitor.identity
    end

    def persist_credit(conversion, credit)
      AttributionCredit.create!(
        account: account,
        conversion: conversion,
        attribution_model: attribution_model,
        model_version: attribution_model.version,
        session_id: credit[:session_id],
        channel: credit[:channel],
        credit: credit[:credit],
        revenue_credit: credit[:revenue_credit],
        utm_source: credit[:utm_source],
        utm_medium: credit[:utm_medium],
        utm_campaign: credit[:utm_campaign],
        is_test: conversion.is_test
      )
    end

    def update_account_usage
      account.increment_reruns_used!(rerun_job.total_conversions)
    end

    def attribution_model
      @attribution_model ||= rerun_job.attribution_model
    end

    def account
      @account ||= rerun_job.account
    end
  end
end
