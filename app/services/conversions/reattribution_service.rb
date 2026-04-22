# frozen_string_literal: true

module Conversions
  class ReattributionService < ApplicationService
    def initialize(conversion)
      @conversion = conversion
    end

    private

    attr_reader :conversion

    def run
      return error_result([ "Conversion has no identity" ]) unless identity

      AttributionCredit.without_dashboard_cache_invalidation do
        with_conversion_lock do
          delete_existing_credits
          calculate_new_credits
        end
      end

      Dashboard::CacheInvalidator.new(conversion.account).call
      success_result(credits_by_model: credits_by_model)
    end

    def with_conversion_lock
      lock_key = conversion.id % (2**31)
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{lock_key})")
        yield
      end
    end

    def identity
      @identity ||= conversion.visitor.identity
    end

    def delete_existing_credits
      conversion.attribution_credits.destroy_all
    end

    def calculate_new_credits
      @credits_by_model = active_models.each_with_object({}) do |model, hash|
        credits = calculate_and_persist_credits(model)
        hash[model.name] = credits
      end
    end

    def credits_by_model
      @credits_by_model
    end

    def calculate_and_persist_credits(model)
      calculator_credits(model).map { |credit| persist_credit(model, credit) }
    end

    def calculator_credits(model)
      Attribution::CrossDeviceCalculator.new(
        conversion: conversion,
        identity: identity,
        attribution_model: model
      ).call
    end

    def persist_credit(model, credit)
      AttributionCredit.create!(
        account: conversion.account,
        conversion: conversion,
        attribution_model: model,
        session_id: credit[:session_id],
        channel: credit[:channel],
        credit: credit[:credit],
        revenue_credit: credit[:revenue_credit],
        utm_source: credit[:utm_source],
        utm_medium: credit[:utm_medium],
        utm_campaign: credit[:utm_campaign],
        is_test: conversion.is_test
      )

      credit
    end

    def active_models
      @active_models ||= conversion.account.attribution_models.active
    end
  end
end
