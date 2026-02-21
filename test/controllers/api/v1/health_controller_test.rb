# frozen_string_literal: true

require "test_helper"

class Api::V1::HealthControllerTest < ActionDispatch::IntegrationTest
  test "should return healthy status" do
    get api_v1_health_path

    assert_response :success
    assert_equal "ok", json_response["status"]
  end

  test "should return API version" do
    get api_v1_health_path

    assert_response :success
    assert_equal "1.0.0", json_response["version"]
  end

  test "should not require authentication" do
    get api_v1_health_path

    assert_response :success
    assert_equal "ok", json_response["status"]
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
