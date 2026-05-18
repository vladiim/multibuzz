# frozen_string_literal: true

module Mcp
  module Tools
    # Shared behaviour for the three data tools. Each subclass declares its own
    # tool_name / description / input_schema and a `call` that delegates here
    # with the matching DataDownloads query service.
    class Base < ::MCP::Tool
      class << self
        private

        def query(service_class, server_context:, args:)
          params = {
            date_range: date_range(args[:start_date], args[:end_date]),
            channels: args[:channels],
            funnel: args[:funnel],
            page: args[:page],
            per_page: args[:per_page],
            test_mode: server_context[:api_key].test?
          }
          success_response(service_class.new(server_context[:account], params).call)
        rescue Date::Error
          error_response("Invalid date format. Use YYYY-MM-DD.")
        end

        def date_range(start_date, end_date)
          return nil if start_date.blank? || end_date.blank?

          { start_date: start_date, end_date: end_date }
        end

        def success_response(result)
          ::MCP::Tool::Response.new(
            [ { type: "text", text: result.to_json } ],
            structured_content: result
          )
        end

        def error_response(message)
          payload = { error: message }
          ::MCP::Tool::Response.new(
            [ { type: "text", text: payload.to_json } ],
            structured_content: payload,
            error: true
          )
        end
      end
    end
  end
end
