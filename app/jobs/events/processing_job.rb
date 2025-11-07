module Events
  class ProcessingJob < ApplicationJob
    queue_as :default

    def perform(account_id, event_data)
      @account_id = account_id
      @event_data = event_data

      process_event
    end

    private

    attr_reader :account_id, :event_data

    def process_event
      result = Events::ProcessingService.new(account, event_data).call

      log_error(result[:errors]) unless result[:success]
    end

    def account
      @account ||= Account.find(account_id)
    end

    def log_error(errors)
      Rails.logger.error("Failed to process event: #{errors.join(', ')}")
    end
  end
end
