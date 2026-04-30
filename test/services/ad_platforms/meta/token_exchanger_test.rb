# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Meta::TokenExchangerTest < ActiveSupport::TestCase
  test "returns success with access_token from a valid response body" do
    result = exchanger(success_body).call

    assert result[:success]
    assert_equal "EAATest123", result[:access_token]
  end

  test "computes expires_at from expires_in seconds" do
    freeze_time do
      result = exchanger(success_body).call

      assert_equal 7200.seconds.from_now.to_i, result[:expires_at].to_i
    end
  end

  test "returns the Meta error message when body contains an error" do
    result = exchanger("error" => { "message" => "Invalid OAuth access token", "code" => 190 }).call

    refute result[:success]
    assert_includes result[:errors].first, "Invalid OAuth access token"
  end

  test "returns a missing-field error when access_token is absent" do
    result = exchanger("token_type" => "bearer").call

    refute result[:success]
    assert_includes result[:errors].first, "access_token"
  end

  test "returns a parse error when body is nil" do
    result = AdPlatforms::Meta::TokenExchanger.new(body: nil).call

    refute result[:success]
  end

  test "treats missing expires_in as expired-now" do
    freeze_time do
      result = exchanger("access_token" => "x").call

      assert_equal Time.current.to_i, result[:expires_at].to_i
    end
  end

  private

  def exchanger(body)
    AdPlatforms::Meta::TokenExchanger.new(body: body)
  end

  def success_body
    { "access_token" => "EAATest123", "token_type" => "bearer", "expires_in" => 7200 }
  end
end
