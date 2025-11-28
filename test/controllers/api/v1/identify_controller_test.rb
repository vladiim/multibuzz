require "test_helper"

class Api::V1::IdentifyControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
  end

  test "creates identity with traits" do
    assert_difference -> { account.identities.unscope(where: :is_test).test_data.count } do
      post api_v1_identify_path, params: identify_params, headers: auth_headers, as: :json
    end

    assert_response :ok

    identity = account.identities.unscope(where: :is_test).test_data.find_by(external_id: "user_123")
    assert_equal "jane@example.com", identity.traits["email"]
    assert_equal "Jane", identity.traits["name"]
  end

  test "links visitor to identity when visitor_id provided" do
    visitor = account.visitors.unscope(where: :is_test).create!(
      visitor_id: "vis_existing",
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      is_test: true
    )

    post api_v1_identify_path,
      params: identify_params.merge(visitor_id: "vis_existing"),
      headers: auth_headers,
      as: :json

    assert_response :ok
    assert_not_nil visitor.reload.identity
    assert_equal "user_123", visitor.identity.external_id
  end

  test "updates existing identity traits" do
    account.identities.unscope(where: :is_test).create!(
      external_id: "user_123",
      traits: { "old" => "trait" },
      first_identified_at: 1.day.ago,
      last_identified_at: 1.day.ago,
      is_test: true
    )

    assert_no_difference -> { account.identities.unscope(where: :is_test).test_data.count } do
      post api_v1_identify_path, params: identify_params, headers: auth_headers, as: :json
    end

    assert_response :ok

    identity = account.identities.unscope(where: :is_test).test_data.find_by(external_id: "user_123")
    assert_equal "jane@example.com", identity.traits["email"]
  end

  test "rejects missing user_id" do
    post api_v1_identify_path, params: { traits: {} }, headers: auth_headers, as: :json

    assert_response :unprocessable_entity
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{plaintext_key}" }
  end

  def identify_params
    {
      user_id: "user_123",
      traits: { email: "jane@example.com", name: "Jane" }
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
