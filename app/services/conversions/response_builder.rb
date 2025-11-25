# frozen_string_literal: true

module Conversions
  class ResponseBuilder
    def initialize(tracking_result)
      @conversion = tracking_result[:conversion]
      @credits_by_model = tracking_result[:attribution_credits] || {}
    end

    def call
      {
        conversion: conversion_response,
        attribution: attribution_response
      }
    end

    private

    attr_reader :conversion, :credits_by_model

    def conversion_response
      {
        id: conversion.prefix_id,
        conversion_type: conversion.conversion_type,
        revenue: conversion.revenue&.to_s,
        converted_at: conversion.converted_at.iso8601,
        visitor_id: conversion.visitor.prefix_id,
        journey_sessions: conversion.journey_session_ids.size
      }
    end

    def attribution_response
      {
        status: "calculated",
        models: formatted_credits
      }
    end

    def formatted_credits
      credits_by_model.transform_values { |credits| credits.map { |c| format_credit(c) } }
    end

    def format_credit(credit)
      {
        channel: credit[:channel],
        credit: credit[:credit],
        revenue_credit: credit[:revenue_credit]&.to_s,
        utm_source: credit[:utm_source],
        utm_medium: credit[:utm_medium],
        utm_campaign: credit[:utm_campaign]
      }
    end
  end
end
