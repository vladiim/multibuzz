# frozen_string_literal: true

# MCP streamable-HTTP endpoint. Authenticates with the same API keys the JSON
# API uses, then hands the JSON-RPC body to a per-request MCP::Server. Auth is
# independent of Api::V1::BaseController by design — see data_downloads_mcp_spec.
module Mcp
  class ServerController < ActionController::API
    before_action :authenticate_api_key

    def handle
      response_json = mcp_server.handle_json(request.raw_post)

      response_json ? render(json: response_json) : head(:accepted)
    end

    private

    def mcp_server
      ServerFactory.build(account: current_account, api_key: current_api_key)
    end

    attr_reader :current_account, :current_api_key

    def authenticate_api_key
      result = ApiKeys::AuthenticationService.new(request.headers["Authorization"]).call
      return render_unauthorized(result[:error]) unless result[:success]

      @current_account = result[:account]
      @current_api_key = result[:api_key]
      render_unauthorized("Account suspended") unless current_account.active?
    end

    def render_unauthorized(error)
      render json: { error: error }, status: :unauthorized
    end
  end
end
