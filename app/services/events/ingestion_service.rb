module Events
  class IngestionService
    def initialize(account, async: false)
      @account = account
      @async = async
    end

    def call(events_data)
      @events_data = events_data
      @accepted_count = 0
      @rejected = []

      process_events
      build_result
    end

    private

    attr_reader :account, :events_data, :accepted_count, :rejected

    def async?
      @async
    end

    def process_events
      events_data.each_with_index do |event_data, index|
        process_single_event(event_data, index)
      end
    end

    def process_single_event(event_data, index)
      validation_result = validation_result_for(event_data)
      return reject_event(index, validation_result[:errors]) unless validation_result[:valid]

      async? ? enqueue_event(event_data) : process_event_sync(event_data, index)
    end

    def validation_result_for(event_data)
      Events::ValidationService.new(event_data).call
    end

    def enqueue_event(event_data)
      Events::ProcessingJob.perform_later(account.id, event_data)
      @accepted_count += 1
    end

    def process_event_sync(event_data, index)
      processing_result = processing_result_for(event_data)
      return reject_event(index, processing_result[:errors]) unless processing_result[:success]

      @accepted_count += 1
    end

    def processing_result_for(event_data)
      Events::ProcessingService.new(account, event_data).call
    end

    def reject_event(index, errors)
      rejected << { index: index, errors: errors }
    end

    def build_result
      { accepted: accepted_count, rejected: rejected }
    end
  end
end
