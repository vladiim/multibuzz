# frozen_string_literal: true

# Builds a per-request MCP::Server scoped to one account. The server is
# stateless: a fresh instance is constructed for every request, carrying the
# authenticated account in `server_context` so tools and resources can scope
# their queries.
module Mcp
  class ServerFactory
    SERVER_NAME = "mbuzz"
    SERVER_TITLE = "mbuzz attribution data"
    SERVER_VERSION = "1.0.0"

    def self.build(account:, api_key:)
      server = ::MCP::Server.new(
        name: SERVER_NAME,
        title: SERVER_TITLE,
        version: SERVER_VERSION,
        tools: [ Tools::GetConversions, Tools::GetFunnel, Tools::GetSpend ],
        resources: [ Resources::AccountSummary.resource ],
        server_context: { account: account, api_key: api_key }
      )
      server.resources_read_handler { |params, server_context:| read_resource(params, server_context) }
      server
    end

    def self.read_resource(params, server_context)
      return [] unless params[:uri] == Resources::AccountSummary::URI

      summary = Resources::AccountSummary.new(
        account: server_context[:account], api_key: server_context[:api_key]
      ).to_h
      [ { uri: Resources::AccountSummary::URI, mimeType: Resources::AccountSummary::MIME_TYPE, text: summary.to_json } ]
    end
    private_class_method :read_resource
  end
end
