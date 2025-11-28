require "test_helper"

class Api::V1::AliasControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    @identity = account.identities.unscope(where: :is_test).create!(
      external_id: "user_456",
      first_identified_at: Time.current,
      last_identified_at: Time.current,
      is_test: true
    )
    @visitor = account.visitors.unscope(where: :is_test).create!(
      visitor_id: "vis_to_link",
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      is_test: true
    )
  end

  test "links visitor to existing identity" do
    assert_nil @visitor.identity

    post api_v1_alias_path, params: alias_params, headers: auth_headers, as: :json

    assert_response :ok
    assert_equal @identity, @visitor.reload.identity
  end

  test "rejects when visitor not found" do
    post api_v1_alias_path,
      params: { visitor_id: "nonexistent", user_id: "user_456" },
      headers: auth_headers,
      as: :json

    assert_response :unprocessable_entity
  end

  test "rejects when identity not found" do
    post api_v1_alias_path,
      params: { visitor_id: "vis_to_link", user_id: "nonexistent" },
      headers: auth_headers,
      as: :json

    assert_response :unprocessable_entity
  end

  test "rejects missing visitor_id" do
    post api_v1_alias_path,
      params: { user_id: "user_456" },
      headers: auth_headers,
      as: :json

    assert_response :unprocessable_entity
  end

  test "rejects missing user_id" do
    post api_v1_alias_path,
      params: { visitor_id: "vis_to_link" },
      headers: auth_headers,
      as: :json

    assert_response :unprocessable_entity
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{plaintext_key}" }
  end

  def alias_params
    { visitor_id: "vis_to_link", user_id: "user_456" }
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
