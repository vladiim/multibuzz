# frozen_string_literal: true

require "test_helper"

class Api::V1::BaseControllerErrorHandlingTest < ActionDispatch::IntegrationTest
  # --- Our integration: unhandled exceptions return 500 JSON ---

  test "returns 500 JSON on unhandled exception" do
    original = Events::IngestionService.instance_method(:call)
    Events::IngestionService.define_method(:call) { |_| raise StandardError, "unexpected" }

    post api_v1_events_path,
      params: { events: [ { event_type: "page_view", visitor_id: "vis_123" } ] },
      headers: auth_headers,
      as: :json

    assert_response :internal_server_error
    assert_equal "Internal server error", json_response["error"]
  ensure
    Events::IngestionService.define_method(:call, original)
  end

  private

  def json_response
    JSON.parse(response.body)
  end

  def auth_headers
    { "Authorization" => "Bearer #{plaintext_key}" }
  end

  def api_key
    @api_key ||= api_keys(:one)
  end

  def plaintext_key
    @plaintext_key ||= begin
      key = "sk_test_#{SecureRandom.hex(16)}"
      api_key.update_column(:key_digest, Digest::SHA256.hexdigest(key))
      key
    end
  end
end
