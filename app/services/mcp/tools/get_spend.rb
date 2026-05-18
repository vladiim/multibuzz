# frozen_string_literal: true

module Mcp
  module Tools
    class GetSpend < Base
      tool_name "mbuzz_get_spend"
      title "Get ad spend"
      description(
        "Returns ad spend records from connected ad platforms (Google Ads, Meta): one row per " \
        "record with spend, impressions, clicks, platform conversions, and operator metadata tags. " \
        "Use when the user asks about ad costs, campaign spend, or ROAS inputs. " \
        "Dates optional, default last 30 days."
      )
      input_schema(
        properties: {
          start_date: { type: "string", description: "Start date YYYY-MM-DD. Optional." },
          end_date: { type: "string", description: "End date YYYY-MM-DD. Optional." },
          channels: { type: "array", items: { type: "string" }, description: "Filter to these channels. Optional." },
          page: { type: "integer", description: "Page number, default 1." },
          per_page: { type: "integer", description: "Rows per page, 1-1000, default 100." }
        }
      )
      annotations(read_only_hint: true)

      class << self
        def call(server_context:, **args)
          query(DataDownloads::SpendQueryService, server_context: server_context, args: args)
        end
      end
    end
  end
end
