# frozen_string_literal: true

module Mcp
  module Tools
    class GetFunnel < Base
      tool_name "mbuzz_get_funnel"
      title "Get funnel timeline"
      description(
        "Returns the funnel timeline: visits, events, and conversions as dated rows with channel " \
        "and UTM data. Use when the user asks about the path to conversion, funnel stages, " \
        "drop-off, or activity over time. Dates optional, default last 30 days."
      )
      input_schema(
        properties: {
          start_date: { type: "string", description: "Start date YYYY-MM-DD. Optional." },
          end_date: { type: "string", description: "End date YYYY-MM-DD. Optional." },
          channels: { type: "array", items: { type: "string" }, description: "Filter to these channels. Optional." },
          funnel: { type: "string", description: "Filter to a named funnel. Optional." },
          page: { type: "integer", description: "Page number, default 1." },
          per_page: { type: "integer", description: "Rows per page, 1-1000, default 100." }
        }
      )
      annotations(read_only_hint: true)

      class << self
        def call(server_context:, **args)
          query(DataDownloads::FunnelQueryService, server_context: server_context, args: args)
        end
      end
    end
  end
end
