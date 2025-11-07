module Api
  module V1
    class EventsController < BaseController
      def create
        return render_bad_request("Missing 'events' parameter") unless events_param_present?
        return render_bad_request("Events must be an array") unless events_param_array?

        process_events
      end

      private

      def events_param_present?
        params.key?(:events)
      end

      def events_param_array?
        params[:events].is_a?(Array)
      end

      def process_events
        return render_accepted(ingestion_result) if ingestion_result[:rejected].empty?

        render_unprocessable(ingestion_result)
      end

      def ingestion_result
        @ingestion_result ||= Events::IngestionService.new(current_account).call(events_data)
      end

      def events_data
        params[:events].map(&:to_unsafe_h)
      end

      def render_accepted(result)
        render json: result, status: :accepted
      end
    end
  end
end
