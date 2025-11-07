require "test_helper"

class Api::V1::HealthControllerTest < ActionDispatch::IntegrationTest
  test "should return healthy status" do
    get api_v1_health_path

    assert_response :success
    assert_equal "ok", json_response["status"]
    assert json_response["timestamp"].present?
  end

  test "should not require authentication" do
    get api_v1_health_path

    assert_response :success
    assert_equal "ok", json_response["status"]
  end

  test "should include database connectivity check" do
    get api_v1_health_path

    assert_response :success
    assert json_response["checks"]["database"]
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
