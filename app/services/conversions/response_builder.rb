# frozen_string_literal: true

module Conversions
  class ResponseBuilder
    def initialize(tracking_result)
      @conversion = tracking_result[:conversion]
    end

    def call
      {
        conversion: conversion_response,
        attribution: attribution_response
      }
    end

    private

    attr_reader :conversion

    def conversion_response
      {
        id: conversion.prefix_id,
        conversion_type: conversion.conversion_type,
        revenue: conversion.revenue&.to_s,
        converted_at: conversion.converted_at.iso8601,
        visitor_id: conversion.visitor.prefix_id
      }
    end

    def attribution_response
      { status: "pending" }
    end
  end
end
