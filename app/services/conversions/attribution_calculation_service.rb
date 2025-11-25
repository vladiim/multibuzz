# frozen_string_literal: true

module Conversions
  class AttributionCalculationService < ApplicationService
    def initialize(conversion)
      @conversion = conversion
    end

    private

    attr_reader :conversion

    def run
      success_result(credits_by_model: credits_by_model)
    end

    def credits_by_model
      @credits_by_model ||= active_models.each_with_object({}) do |model, hash|
        credits = calculate_and_persist_credits(model)
        hash[model.name] = credits
      end
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
        utm_campaign: credit[:utm_campaign]
      )

      credit
    end

    def active_models
      @active_models ||= conversion.account.attribution_models.active
    end
  end
end
