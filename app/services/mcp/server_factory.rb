# frozen_string_literal: true

# Builds a per-request MCP::Server scoped to one account. The server is
# stateless: a fresh instance is constructed for every request, carrying the
# authenticated account in `server_context` so tools can scope their queries.
module Mcp
  class ServerFactory
    SERVER_NAME = "mbuzz"
    SERVER_TITLE = "mbuzz attribution data"
    SERVER_VERSION = "1.0.0"

    def self.build(account:, api_key:)
      ::MCP::Server.new(
        name: SERVER_NAME,
        title: SERVER_TITLE,
        version: SERVER_VERSION,
        tools: [],
        resources: [],
        server_context: { account: account, api_key: api_key }
      )
    end
  end
end
