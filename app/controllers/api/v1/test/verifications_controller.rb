module Api
  module V1
    module Test
      class VerificationsController < BaseController
        before_action :require_test_environment
        before_action :require_test_key
        before_action :require_visitor_id

        def show
          render json: VerificationPresenter.new(current_account, visitor_id, user_id).to_h
        end

        def destroy
          return render json: not_found_response unless visitor

          VisitorCleanupService.new(visitor).call
          render json: success_response("Test data cleaned up")
        end

        private

        def require_test_environment
          return if Rails.env.local?

          render json: forbidden_response("test/development environments only"), status: :forbidden
        end

        def require_test_key
          return if current_api_key.test?

          render json: forbidden_response("test API keys (sk_test_*) only"), status: :forbidden
        end

        def require_visitor_id
          return if visitor_id.present?

          render_bad_request("visitor_id is required")
        end

        def visitor_id = params[:visitor_id]
        def user_id = params[:user_id]
        def visitor = @visitor ||= current_account.visitors.find_by(visitor_id: visitor_id)

        def forbidden_response(message) = { error: "This endpoint only works with #{message}" }
        def success_response(message) = { success: true, message: message }
        def not_found_response = success_response("Visitor not found")
      end

      # Presents verification data for a visitor
      class VerificationPresenter
        def initialize(account, visitor_id, user_id = nil)
          @account = account
          @visitor_id = visitor_id
          @user_id = user_id
        end

        def to_h
          {
            visitor: visitor_data,
            sessions: sessions_data,
            events: events_data,
            identity: identity_data,
            conversions: conversions_data
          }
        end

        private

        attr_reader :account, :visitor_id, :user_id

        def visitor
          @visitor ||= account.visitors.find_by(visitor_id: visitor_id)
        end

        def identity
          @identity ||= user_id.present? ? account.identities.find_by(user_id: user_id) : nil
        end

        def resolved_identity
          identity || visitor&.identity
        end

        def visitor_data
          return nil unless visitor

          {
            visitor_id: visitor.visitor_id,
            identity_id: visitor.identity_id,
            first_seen_at: visitor.first_seen_at,
            last_seen_at: visitor.last_seen_at,
            created_at: visitor.created_at
          }
        end

        def sessions_data
          return [] unless visitor

          visitor.sessions.order(started_at: :desc).map { |s| session_to_h(s) }
        end

        def session_to_h(session)
          {
            session_id: session.session_id,
            started_at: session.started_at,
            ended_at: session.ended_at,
            initial_referrer: session.initial_referrer,
            initial_utm: session.initial_utm,
            channel: session.channel
          }
        end

        def events_data
          return [] unless visitor

          visitor.events.order(occurred_at: :desc).limit(100).map { |e| event_to_h(e) }
        end

        def event_to_h(event)
          {
            event_type: event.event_type,
            occurred_at: event.occurred_at,
            properties: event.properties,
            url: event.url
          }
        end

        def identity_data
          return nil unless resolved_identity

          {
            user_id: resolved_identity.external_id,
            traits: resolved_identity.traits,
            first_identified_at: resolved_identity.first_identified_at,
            last_identified_at: resolved_identity.last_identified_at
          }
        end

        def conversions_data
          return [] unless visitor || identity

          conversions_scope.order(converted_at: :desc).map { |c| conversion_to_h(c) }
        end

        def conversions_scope
          identity ? identity.conversions : visitor_conversions
        end

        def visitor_conversions
          Conversion.joins(:visitor).where(visitors: { id: visitor.id })
        end

        def conversion_to_h(conversion)
          {
            conversion_type: conversion.conversion_type,
            converted_at: conversion.converted_at,
            revenue: conversion.revenue,
            currency: conversion.currency,
            is_acquisition: conversion.is_acquisition,
            properties: conversion.properties
          }
        end
      end

      # Cleans up visitor test data
      class VisitorCleanupService
        def initialize(visitor)
          @visitor = visitor
        end

        def call
          visitor.events.destroy_all
          visitor.sessions.destroy_all
          visitor.destroy
        end

        private

        attr_reader :visitor
      end
    end
  end
end
