# frozen_string_literal: true

module Conversions
  class TrackingService < ApplicationService
    FINGERPRINT_WINDOW = 30.seconds
    FINGERPRINT_LENGTH = 32

    def initialize(account, params, is_test: false)
      @account = account
      @event_id = params[:event_id]
      @visitor_id_param = params[:visitor_id]
      @conversion_type = params[:conversion_type]
      @revenue = params[:revenue]
      @currency = params[:currency]
      @funnel = params[:funnel]
      @properties = params[:properties] || {}
      @is_test = is_test
      @user_id = params[:user_id]
      @is_acquisition = params[:is_acquisition] || false
      @inherit_acquisition = params[:inherit_acquisition] || false
      @ip = params[:ip]
      @user_agent = params[:user_agent]
      @idempotency_key = params[:idempotency_key]
    end

    private

    attr_reader :account, :event_id, :visitor_id_param, :conversion_type, :revenue, :currency,
      :funnel, :properties, :is_test, :user_id, :is_acquisition, :inherit_acquisition, :ip, :user_agent,
      :idempotency_key

    def run
      return validation_error if validation_error

      conversion # resolve before side-effects so duplicate? is set
      update_session_activity
      increment_usage! unless duplicate?
      success_result(conversion: conversion, duplicate: duplicate?)
    end

    def update_session_activity
      resolved_session&.update!(last_activity_at: Time.current)
    end

    def increment_usage!
      Billing::UsageCounter.new(account).increment!
    end

    def validation_error
      return error_result([ "event_id or visitor_id is required" ]) unless has_identifier?
      return error_result([ "conversion_type is required" ]) unless conversion_type.present?
      return error_result([ "Event not found" ]) if event_id.present? && !event
      return error_result([ "Event belongs to different account" ]) if event && !event_belongs_to_account?
      return error_result([ "Visitor not found" ]) unless resolved_visitor

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

    # Resolution: event takes precedence, then visitor_id lookup, then fingerprint fallback
    def resolved_visitor
      @resolved_visitor ||= event&.visitor || find_visitor_by_id || find_visitor_by_fingerprint
    end

    def find_visitor_by_id
      return nil unless visitor_id_param.present?

      account.visitors.find_by(visitor_id: visitor_id_param)
    end

    def find_visitor_by_fingerprint
      return nil unless can_fingerprint?

      recent_fingerprint_session&.visitor
    end

    def can_fingerprint?
      ip.present? && user_agent.present?
    end

    def recent_fingerprint_session
      account.sessions
        .where(device_fingerprint: device_fingerprint)
        .where("sessions.created_at > ?", FINGERPRINT_WINDOW.ago)
        .order(:created_at)
        .first
    end

    def device_fingerprint
      @device_fingerprint ||= Digest::SHA256.hexdigest("#{ip}|#{user_agent}")[0, FINGERPRINT_LENGTH]
    end

    def resolved_session
      @resolved_session ||= event&.session || resolved_visitor&.sessions&.order(started_at: :desc)&.first
    end

    def conversion
      @conversion ||= existing_idempotent_conversion || create_conversion
    end

    def existing_idempotent_conversion
      return nil unless idempotency_key.present?

      existing = account.conversions.find_by(idempotency_key: idempotency_key)
      return nil unless existing

      @duplicate = true
      existing
    end

    def duplicate?
      @duplicate || false
    end

    def create_conversion
      Conversion.create!(
        account: account,
        visitor_id: resolved_visitor.id,
        session_id: resolved_session&.id,
        event_id: event&.id,
        conversion_type: conversion_type,
        revenue: normalized_revenue,
        currency: currency.presence || "USD",
        funnel: funnel,
        properties: normalized_properties,
        converted_at: conversion_timestamp,
        journey_session_ids: [],
        is_test: is_test,
        identity_id: resolved_identity&.id,
        is_acquisition: is_acquisition,
        idempotency_key: idempotency_key
      ).tap { |c| c.inherit_acquisition = inherit_acquisition }
    rescue ActiveRecord::RecordNotUnique
      @duplicate = true
      account.conversions.find_by!(idempotency_key: idempotency_key)
    end

    def resolved_identity
      @resolved_identity ||= identity_from_user_id || resolved_visitor&.identity
    end

    def identity_from_user_id
      return nil unless user_id.present?

      account.identities.find_by(external_id: user_id)
    end

    # Flatten nested "properties" key if present
    # Input:  { "url" => "...", "properties" => { "location" => "Sydney" } }
    # Output: { "url" => "...", "location" => "Sydney" }
    def normalized_properties
      props = properties.respond_to?(:to_unsafe_h) ? properties.to_unsafe_h : properties.to_h
      return props unless props.is_a?(Hash)

      nested = props["properties"] || props[:properties]
      return props unless nested.respond_to?(:to_h)

      nested_hash = nested.respond_to?(:to_unsafe_h) ? nested.to_unsafe_h : nested.to_h
      props.except("properties", :properties).merge(nested_hash)
    end

    def conversion_timestamp
      event&.occurred_at || Time.current
    end

    def normalized_revenue
      return nil if revenue.nil?
      return nil if revenue.to_f.negative?

      revenue
    rescue ArgumentError, TypeError, NoMethodError
      nil
    end
  end
end
