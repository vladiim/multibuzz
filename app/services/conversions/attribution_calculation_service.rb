# frozen_string_literal: true

module Conversions
  class AttributionCalculationService < ApplicationService
    def initialize(conversion)
      @conversion = conversion
    end

    private

    attr_reader :conversion

    def run
      if should_inherit_acquisition?
        inherit_acquisition_attribution
      else
        calculate_fresh_attribution
      end

      success_result(credits_by_model: credits_by_model)
    end

    # Acquisition inheritance
    def should_inherit_acquisition?
      conversion.inherit_acquisition? && acquisition_conversion.present?
    end

    def acquisition_conversion
      return nil unless conversion.identity_id.present?

      @acquisition_conversion ||= conversion.account.conversions
        .where(identity_id: conversion.identity_id, is_acquisition: true)
        .order(converted_at: :desc)
        .first
    end

    def inherit_acquisition_attribution
      @credits_by_model = active_models.each_with_object({}) do |model, hash|
        hash[model.name] = inherit_credits_for_model(model)
      end

      inherit_journey_session_ids
    end

    def inherit_journey_session_ids
      return unless acquisition_conversion.journey_session_ids.any?

      conversion.update_column(:journey_session_ids, acquisition_conversion.journey_session_ids)
    end

    def inherit_credits_for_model(model)
      acquisition_conversion.attribution_credits
        .where(attribution_model: model)
        .map { |source| create_inherited_credit(model, source) }
        .map { |credit| credit_to_hash(credit) }
    end

    def create_inherited_credit(model, source)
      AttributionCredit.create!(
        inherited_credit_attributes(model, source)
      )
    end

    def inherited_credit_attributes(model, source)
      {
        account: conversion.account,
        conversion: conversion,
        attribution_model: model,
        session_id: source.session_id,
        channel: source.channel,
        credit: source.credit,
        revenue_credit: source.credit * (conversion.revenue || 0),
        utm_source: source.utm_source,
        utm_medium: source.utm_medium,
        utm_campaign: source.utm_campaign,
        is_test: conversion.is_test
      }
    end

    # Fresh attribution calculation
    def calculate_fresh_attribution
      store_journey_session_ids

      @credits_by_model = active_models.each_with_object({}) do |model, hash|
        hash[model.name] = calculate_model_safely(model)
      end
    end

    def calculate_model_safely(model)
      calculate_and_persist_credits(model)
    rescue StandardError => e
      Rails.logger.error(
        "[Attribution] #{model.name} failed for conversion #{conversion.id}: #{e.message}"
      )
      []
    end

    def store_journey_session_ids
      session_ids = touchpoints.map { |t| t[:session_id] }
      conversion.update_column(:journey_session_ids, session_ids) if session_ids.any?
    end

    def touchpoints
      @touchpoints ||= Attribution::JourneyBuilder.new(
        visitor: conversion.visitor,
        converted_at: conversion.converted_at,
        lookback_days: AttributionAlgorithms::DEFAULT_LOOKBACK_DAYS
      ).call
    end

    def credits_by_model
      @credits_by_model ||= {}
    end

    def calculate_and_persist_credits(model)
      calculator_credits(model).map { |credit| persist_credit(model, credit) }
    end

    def calculator_credits(model)
      Attribution::Calculator.new(
        conversion: conversion,
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

    def credit_to_hash(credit)
      {
        session_id: credit.session_id,
        channel: credit.channel,
        credit: credit.credit,
        revenue_credit: credit.revenue_credit,
        utm_source: credit.utm_source,
        utm_medium: credit.utm_medium,
        utm_campaign: credit.utm_campaign
      }
    end

    def active_models
      @active_models ||= conversion.account.attribution_models.active
    end
  end
end
