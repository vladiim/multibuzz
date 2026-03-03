# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class AdPlatforms::Google::ListCustomersTest < ActiveSupport::TestCase
  test "returns customer list on success" do
    stub_api(list_response: accessible_response, detail_responses: { "1234567890" => customer_detail }) do
      result = service.call
      customer = result[:customers].first

      assert result[:success]
      assert_equal 1, result[:customers].size
      assert_equal({ id: "1234567890", name: "Acme Ads", currency: "USD" }, customer)
    end
  end

  test "excludes manager accounts" do
    details = {
      "1234567890" => customer_detail,
      "9999999999" => manager_detail
    }

    stub_api(list_response: multi_accessible_response, detail_responses: details) do
      result = service.call

      assert result[:success]
      assert_equal 1, result[:customers].size
      assert_equal "1234567890", result[:customers].first[:id]
    end
  end

  test "returns error when list request fails" do
    stub_api(list_response: error_response, detail_responses: {}) do
      result = service.call

      assert_not result[:success]
      assert_predicate result[:errors], :present?
    end
  end

  test "returns empty list when no non-manager accounts" do
    stub_api(list_response: single_manager_response, detail_responses: { "9999999999" => manager_detail }) do
      result = service.call

      assert result[:success]
      assert_empty result[:customers]
    end
  end

  private

  def service = @service ||= AdPlatforms::Google::ListCustomers.new(access_token: "test_token")

  def accessible_response
    { "resourceNames" => [ "customers/1234567890" ] }
  end

  def multi_accessible_response
    { "resourceNames" => [ "customers/1234567890", "customers/9999999999" ] }
  end

  def single_manager_response
    { "resourceNames" => [ "customers/9999999999" ] }
  end

  def customer_detail
    {
      "results" => [ {
        "customer" => {
          "id" => "1234567890",
          "descriptiveName" => "Acme Ads",
          "currencyCode" => "USD",
          "manager" => false
        }
      } ]
    }
  end

  def manager_detail
    {
      "results" => [ {
        "customer" => {
          "id" => "9999999999",
          "descriptiveName" => "MCC Account",
          "currencyCode" => "USD",
          "manager" => true
        }
      } ]
    }
  end

  def error_response
    nil
  end

  def stub_api(list_response:, detail_responses:)
    list_stub = build_response(list_response)
    detail_stubs = detail_responses.transform_values { |v| build_response(v) }

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      Net::HTTP.stub(:start, ->(_host, _port, **_opts, &block) {
        block.call(build_mock_http(list_stub, detail_stubs))
      }) do
        yield
      end
    end
  end

  def build_mock_http(list_stub, detail_stubs)
    mock = Object.new
    mock.define_singleton_method(:request) do |req|
      path = req.uri&.path || req.path
      next list_stub if path&.include?("listAccessibleCustomers")

      customer_id = path&.match(%r{customers/(\d+)})&.[](1)
      detail_stubs[customer_id] || list_stub
    end
    mock
  end

  def build_response(body)
    if body.nil?
      response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
      response.define_singleton_method(:body) { '{"error":{"message":"Request failed"}}' }
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess ? false : super(klass) }
      response
    else
      response = Net::HTTPOK.new("1.1", "200", "OK")
      json = body.to_json
      response.define_singleton_method(:body) { json }
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess ? true : super(klass) }
      response
    end
  end

  def test_credentials
    { client_id: "test_client_id", client_secret: "test_client_secret", developer_token: "test_dev_token" }
  end
end
