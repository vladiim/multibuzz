# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class AdPlatforms::Google::TokenClientTest < ActiveSupport::TestCase
  test "returns parsed body on success" do
    stub_http(success: true, body: success_body) do
      result = client.call

      assert result[:success]
      assert_equal "the_token", result[:body].fetch("access_token")
    end
  end

  test "returns error on failed response" do
    stub_http(success: false, body: error_body) do
      result = client.call

      assert_not result[:success]
      assert_includes result[:errors].first, "Bad Request"
    end
  end

  test "returns error on unparseable response" do
    stub_http(success: false, body: "not json") do
      result = client.call

      assert_not result[:success]
      assert_includes result[:errors].first, "unexpected response"
    end
  end

  test "merges client credentials into params" do
    captured_request = nil

    mock_response = Minitest::Mock.new
    mock_response.expect :is_a?, true, [ Net::HTTPSuccess ]
    mock_response.expect :body, success_body

    Net::HTTP.stub :start, ->(*, **, &block) {
      mock_http = Minitest::Mock.new
      mock_http.expect(:request, mock_response) { |req| captured_request = req; true }
      block.call(mock_http)
    } do
      AdPlatforms::Google.stub(:credentials, test_credentials) do
        client.call
      end
    end

    params = URI.decode_www_form(captured_request.body).to_h

    assert_equal "test_grant", params["grant_type"]
    assert_equal "test_client_id", params["client_id"]
    assert_equal "test_client_secret", params["client_secret"]
  end

  private

  def client = @client ||= AdPlatforms::Google::TokenClient.new(grant_type: "test_grant")

  def success_body
    { "access_token" => "the_token", "expires_in" => 3600 }.to_json
  end

  def error_body
    { "error" => "invalid_grant", "error_description" => "Bad Request" }.to_json
  end

  def test_credentials
    { client_id: "test_client_id", client_secret: "test_client_secret" }
  end

  def stub_http(success:, body:)
    mock_response = Minitest::Mock.new
    mock_response.expect :is_a?, success, [ Net::HTTPSuccess ]
    mock_response.expect :body, body

    mock_http = Minitest::Mock.new
    mock_http.expect :request, mock_response, [ Net::HTTP::Post ]

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      Net::HTTP.stub :start, ->(*, **, &block) { block.call(mock_http) } do
        yield
      end
    end
  end
end
