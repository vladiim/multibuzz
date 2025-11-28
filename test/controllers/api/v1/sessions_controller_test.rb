require "test_helper"

class Api::V1::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
  end

  test "creates visitor and session with UTM data" do
    assert_difference -> { account.visitors.unscope(where: :is_test).test_data.count } do
      assert_difference -> { account.sessions.unscope(where: :is_test).test_data.count } do
        post api_v1_sessions_path, params: session_payload, headers: auth_headers, as: :json
      end
    end

    assert_response :accepted

    session = account.sessions.unscope(where: :is_test).test_data.last
    assert_equal "google", session.initial_utm["utm_source"]
    assert_equal "cpc", session.initial_utm["utm_medium"]
    assert_equal "paid_search", session.channel
  end

  test "determines direct channel when no UTMs or referrer" do
    post api_v1_sessions_path, params: direct_session_payload, headers: auth_headers, as: :json

    assert_response :accepted

    session = account.sessions.unscope(where: :is_test).test_data.last
    assert_equal "direct", session.channel
  end

  test "determines organic_search from google referrer" do
    post api_v1_sessions_path, params: organic_session_payload, headers: auth_headers, as: :json

    assert_response :accepted

    session = account.sessions.unscope(where: :is_test).test_data.last
    assert_equal "organic_search", session.channel
  end

  test "rejects missing required fields" do
    payload = { session: { visitor_id: SecureRandom.hex(32) } } # missing session_id and url

    post api_v1_sessions_path, params: payload, headers: auth_headers, as: :json

    assert_response :unprocessable_entity
  end

  test "rejects missing session param" do
    post api_v1_sessions_path, params: {}, headers: auth_headers, as: :json

    assert_response :bad_request
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{plaintext_key}" }
  end

  def session_payload
    {
      session: {
        visitor_id: SecureRandom.hex(32),
        session_id: SecureRandom.hex(32),
        url: "https://example.com/landing?utm_source=google&utm_medium=cpc"
      }
    }
  end

  def direct_session_payload
    {
      session: {
        visitor_id: SecureRandom.hex(32),
        session_id: SecureRandom.hex(32),
        url: "https://example.com/page"
      }
    }
  end

  def organic_session_payload
    {
      session: {
        visitor_id: SecureRandom.hex(32),
        session_id: SecureRandom.hex(32),
        url: "https://example.com/page",
        referrer: "https://www.google.com/search?q=test"
      }
    }
  end

  def account
    @account ||= accounts(:one)
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
