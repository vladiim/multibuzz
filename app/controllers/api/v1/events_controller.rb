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
        result = ingestion_result
        process_identifiers
        render_accepted(result)
      end

      def set_cookies
        response.headers["Set-Cookie"] = [
          visitor_identification[:set_cookie],
          session_identification[:set_cookie]
        ].compact.join(", ")
      end

      def process_identifiers
        identifier_params.each { |params| identify_visitor(params) }
      end

      def identifier_params
        events_data
          .map { |event| build_identifier_params(event) }
          .compact
      end

      def build_identifier_params(event_data)
        identifier = event_data["identifier"] || event_data[:identifier]
        return unless identifier.present?

        user_id = identifier["email"] || identifier[:email] ||
          identifier["user_id"] || identifier[:user_id] ||
          identifier.values.first
        return unless user_id.present?

        {
          user_id: user_id,
          visitor_id: event_data["visitor_id"] || event_data[:visitor_id] || visitor_identification[:visitor_id]
        }
      end

      def identify_visitor(params)
        Identities::IdentificationService.new(
          current_account,
          params,
          is_test: current_api_key.test?
        ).call
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
        @ingestion_result ||= Events::IngestionService.new(
          current_account,
          async: false,
          is_test: current_api_key.test?
        ).call(enriched_events_data)
      end

      def enriched_events_data
        events_data.map { |event_data| enrich_event(event_data) }
      end

      def enrich_event(event_data)
        Events::EnrichmentService.new(
          request,
          event_data,
          visitor_id: resolve_visitor_id(event_data),
          session_id: resolve_session_id(event_data)
        ).call
      end

      def resolve_visitor_id(event_data)
        event_data["visitor_id"] || event_data[:visitor_id] || visitor_identification[:visitor_id]
      end

      def resolve_session_id(event_data)
        event_data["session_id"] || event_data[:session_id] || session_identification[:session_id]
      end

      def events_data
        @events_data ||= params[:events].map(&:to_unsafe_h)
      end

      def render_accepted(result)
        render json: result, status: :accepted
      end
    end
  end
end
