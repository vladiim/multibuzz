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
        set_cookies
        render_accepted(ingestion_result)
      end

      def set_cookies
        response.headers["Set-Cookie"] = [
          visitor_identification[:set_cookie],
          session_identification[:set_cookie]
        ].compact.join(", ")
      end

      def visitor_identification
        @visitor_identification ||= Visitors::IdentificationService.new(request, current_account).call
      end

      def session_identification
        @session_identification ||= Sessions::IdentificationService.new(
          request,
          current_account,
          visitor_identification[:visitor_id]
        ).call
      end

      def ingestion_result
        @ingestion_result ||= Events::IngestionService.new(current_account, async: true).call(enriched_events_data)
      end

      def enriched_events_data
        events_data.map { |event_data| enrich_event(event_data) }
      end

      def enrich_event(event_data)
        Events::EnrichmentService.new(request, event_data).call
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
