module Events
  class IngestionService
    def initialize(account)
      @account = account
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

    def process_events
      events_data.each_with_index do |event_data, index|
        process_single_event(event_data, index)
      end
    end

    def process_single_event(event_data, index)
      validation_result = validation_result_for(event_data)
      return reject_event(index, validation_result[:errors]) unless validation_result[:valid]

      processing_result = processing_result_for(event_data)
      return reject_event(index, processing_result[:errors]) unless processing_result[:success]

      @accepted_count += 1
    end

    def validation_result_for(event_data)
      Events::ValidationService.new.call(event_data)
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
