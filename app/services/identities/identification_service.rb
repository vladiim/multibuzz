module Identities
  class IdentificationService < ApplicationService
    def initialize(account, params, is_test: false)
      @account = account
      @user_id = params[:user_id]
      @visitor_id = params[:visitor_id]
      @traits = params[:traits] || {}
      @is_test = is_test
    end

    private

    attr_reader :account, :user_id, :visitor_id, :traits, :is_test

    def run
      return error_result(validation_errors) if invalid?

      persist_identity
      visitor_was_linked = link_visitor_if_present

      success_result(
        identity_id: identity.prefix_id,
        visitor_linked: visitor_was_linked
      )
    end

    def invalid?
      validation_errors.any?
    end

    def validation_errors
      @validation_errors ||= [
        ("user_id is required" unless user_id.present?)
      ].compact
    end

    def persist_identity
      new_traits = traits.respond_to?(:to_unsafe_h) ? traits.to_unsafe_h : traits.to_h
      identity.traits = (identity.traits || {}).deep_merge(new_traits.deep_stringify_keys)
      identity.last_identified_at = Time.current
      identity.save!
    end

    def link_visitor_if_present
      return false unless visitor_id.present?
      return false unless visitor

      visitor.update!(identity: identity)
      update_session_activity
      queue_reattribution_if_needed
      true
    end

    def update_session_activity
      most_recent_session&.update!(last_activity_at: Time.current)
    end

    def most_recent_session
      visitor&.sessions&.order(started_at: :desc)&.first
    end

    def queue_reattribution_if_needed
      conversions_needing_reattribution.each do |conversion|
        Conversions::ReattributionJob.perform_later(conversion.id)
      end
    end

    def conversions_needing_reattribution
      return [] unless identity_visitors.count > 1

      other_visitors_conversions.select do |conversion|
        visitor_has_sessions_in_lookback?(conversion)
      end
    end

    def other_visitors_conversions
      other_visitor_ids = identity.visitors.where.not(id: visitor.id).pluck(:id)
      return [] if other_visitor_ids.empty?

      account.conversions.where(visitor_id: other_visitor_ids)
    end

    def visitor_has_sessions_in_lookback?(conversion)
      lookback_start = conversion.converted_at - AttributionAlgorithms::DEFAULT_LOOKBACK_DAYS.days

      account.sessions
        .where(visitor: visitor)
        .where("started_at >= ?", lookback_start)
        .where("started_at <= ?", conversion.converted_at)
        .exists?
    end

    def identity
      @identity ||= account.identities.find_or_initialize_by(external_id: user_id) do |i|
        i.first_identified_at = Time.current
        i.last_identified_at = Time.current
        i.is_test = is_test
      end
    end

    def visitor
      @visitor ||= account.visitors.find_by(visitor_id: visitor_id)
    end

    def identity_visitors
      identity.visitors
    end
  end
end
