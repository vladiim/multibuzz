# frozen_string_literal: true

module Conversions
  class TrackingService < ApplicationService
    def initialize(account, params)
      @account = account
      @event_id = params[:event_id]
      @conversion_type = params[:conversion_type]
      @revenue = params[:revenue]
    end

    private

    attr_reader :account, :event_id, :conversion_type, :revenue

    def run
      return validation_error if validation_error

      success_result(
        conversion: conversion,
        attribution_credits: attribution_result[:credits_by_model]
      )
    end

    def validation_error
      return error_result(["event_id is required"]) unless event_id.present?
      return error_result(["conversion_type is required"]) unless conversion_type.present?
      return error_result(["Event not found"]) unless event
      return error_result(["Event belongs to different account"]) unless event_belongs_to_account?

      nil
    end

    def event
      @event ||= Event.find_by_prefix_id(event_id)
    end

    def event_belongs_to_account?
      event.account_id == account.id
    end

    def conversion
      @conversion ||= Conversion.create!(
        account: account,
        visitor_id: event.visitor_id,
        session_id: event.session_id,
        event_id: event.id,
        conversion_type: conversion_type,
        revenue: revenue,
        converted_at: event.occurred_at,
        journey_session_ids: []
      )
    end

    def attribution_result
      @attribution_result ||= AttributionCalculationService.new(conversion).call
    end
  end
end
