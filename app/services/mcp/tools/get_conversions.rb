# frozen_string_literal: true

module Mcp
  module Tools
    class GetConversions < Base
      tool_name "mbuzz_get_conversions"
      title "Get conversions"
      description(
        "Returns attributed conversions for the account: one row per conversion with channel, " \
        "attribution model, credit, revenue, and UTM data. Use when the user asks which channels " \
        "or campaigns drove conversions or revenue, or about attributed ROAS. " \
        "Dates optional, default last 30 days."
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
          query(DataDownloads::ConversionsQueryService, server_context: server_context, args: args)
        end
      end
    end
  end
end
