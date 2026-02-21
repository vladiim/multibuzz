# frozen_string_literal: true

module Events
  class IngestionService
    def initialize(account, async: false, is_test: false)
      @account = account
      @async = async
      @is_test = is_test
    end

    def call(events_data)
      @events_data = events_data
      @accepted = []
      @rejected = []

      return billing_blocked_result unless can_ingest?

      process_events
      increment_usage_counter
      build_result
    end

    private

    attr_reader :account, :events_data, :accepted, :rejected, :is_test

    def async?
      @async
    end

    def test_mode?
      is_test
    end

    def process_events
      events_data.each_with_index do |event_data, index|
        process_single_event(event_data, index)
      end
    end

    def process_single_event(event_data, index)
      validation_result = validation_result_for(event_data)
      return reject_event(event_data, index, validation_result[:errors]) unless validation_result[:valid]

      async? ? enqueue_event(event_data) : process_event_sync(event_data, index)
    end

    def validation_result_for(event_data)
      Events::ValidationService.new(event_data).call
    end

    def enqueue_event(event_data)
      Events::ProcessingJob.perform_later(account.id, event_data, is_test)
      accept_event_async(event_data)
    end

    def process_event_sync(event_data, index)
      processing_result = processing_result_for(event_data)
      return reject_event(event_data, index, processing_result[:errors]) unless processing_result[:success]

      accept_event(processing_result[:event], event_data)
    end

    def processing_result_for(event_data)
      Events::ProcessingService.new(account, event_data, is_test: is_test).call
    end

    def accept_event(event, event_data)
      accepted << {
        id: event.prefix_id,
        event_type: event_data["event_type"],
        visitor_id: event_data["visitor_id"],
        session_id: event_data["session_id"],
        status: "accepted"
      }
    end

    def accept_event_async(event_data)
      accepted << {
        id: nil,
        event_type: event_data["event_type"],
        visitor_id: event_data["visitor_id"],
        session_id: event_data["session_id"],
        status: "accepted"
      }
    end

    def reject_event(event_data, index, errors)
      rejected << {
        index: index,
        event_type: event_data["event_type"],
        errors: errors,
        status: "rejected"
      }
    end

    def build_result
      { accepted: accepted.count, rejected: rejected, events: accepted }
    end

    # --- Billing ---

    def can_ingest?
      account.can_ingest_events?
    end

    def billing_blocked_result
      {
        accepted: 0,
        rejected: [],
        events: [],
        billing_blocked: true,
        billing_error: "Account cannot accept events"
      }
    end

    def increment_usage_counter
      return if accepted.empty?

      usage_counter.increment!(accepted.count)
    end

    def usage_counter
      @usage_counter ||= Billing::UsageCounter.new(account)
    end

    def should_lock_events?
      account.should_lock_events?
    end
  end
end
