# frozen_string_literal: true

module Conversions
  class TrackingService < ApplicationService
    def initialize(account, params)
      @account = account
      @event_id = params[:event_id]
      @visitor_id_param = params[:visitor_id]
      @conversion_type = params[:conversion_type]
      @revenue = params[:revenue]
      @properties = params[:properties] || {}
    end

    private

    attr_reader :account, :event_id, :visitor_id_param, :conversion_type, :revenue, :properties

    def run
      return validation_error if validation_error

      enqueue_attribution_calculation

      success_result(conversion: conversion)
    end

    def validation_error
      return error_result(["event_id or visitor_id is required"]) unless has_identifier?
      return error_result(["conversion_type is required"]) unless conversion_type.present?
      return error_result(["Event not found"]) if event_id.present? && !event
      return error_result(["Event belongs to different account"]) if event && !event_belongs_to_account?
      return error_result(["Visitor not found"]) unless resolved_visitor

      nil
    end

    def has_identifier?
      event_id.present? || visitor_id_param.present?
    end

    # Event lookup (when event_id provided)
    def event
      return nil unless event_id.present?

      @event ||= Event.find_by_prefix_id(event_id)
    end

    def event_belongs_to_account?
      event&.account_id == account.id
    end

    # Resolution: event takes precedence, then visitor_id lookup
    def resolved_visitor
      @resolved_visitor ||= event&.visitor || find_visitor_by_id
    end

    def find_visitor_by_id
      return nil unless visitor_id_param.present?

      account.visitors.find_by(visitor_id: visitor_id_param)
    end

    def resolved_session
      @resolved_session ||= event&.session || resolved_visitor&.sessions&.order(started_at: :desc)&.first
    end

    def conversion
      @conversion ||= Conversion.create!(
        account: account,
        visitor_id: resolved_visitor.id,
        session_id: resolved_session&.id,
        event_id: event&.id,
        conversion_type: conversion_type,
        revenue: revenue,
        properties: properties,
        converted_at: conversion_timestamp,
        journey_session_ids: []
      )
    end

    def conversion_timestamp
      event&.occurred_at || Time.current
    end

    def enqueue_attribution_calculation
      AttributionCalculationJob.perform_later(conversion.id)
    end
  end
end
