# frozen_string_literal: true

module Lifecycle
  module Tracker
    module_function

    def track(event_name, account, **properties)
      payload = build_payload(event_name, account, **properties)
      return unless payload
      return record_for_test(payload) if skip_tracking?

      Mbuzz.event(payload[:name], **payload[:properties])
    rescue StandardError
      nil
    end

    RECORDED_EVENTS_THREAD_KEY = :lifecycle_tracker_recorded_events

    def recorded_events
      Thread.current[RECORDED_EVENTS_THREAD_KEY] ||= []
    end

    def reset_recorded_events!
      Thread.current[RECORDED_EVENTS_THREAD_KEY] = []
    end

    def record_for_test(payload)
      recorded_events << payload
      nil
    end

    def build_payload(event_name, account, **properties)
      owner = resolve_owner(account)
      return nil unless owner

      {
        name: event_name,
        properties: { user_id: owner.prefix_id, **standard_properties(account), **properties }
      }
    end

    def resolve_owner(account)
      account.account_memberships.owner.accepted.first&.user
    end

    def standard_properties(account)
      {
        account_id: account.prefix_id,
        account_name: account.name,
        plan: account.plan&.slug || "free",
        billing_status: account.billing_status,
        days_since_signup: ((Time.current - account.created_at) / 1.day).round,
        usage_percentage: account.usage_percentage
      }
    end

    def skip_tracking?
      Rails.env.test?
    end
  end
end
