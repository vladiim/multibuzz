# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class AdPlatforms::Google::SpendSyncServiceTest < ActiveSupport::TestCase
  test "upserts ad spend records from API response" do
    stub_gaql_responses(standard: standard_response, pmax: empty_response) do
      result = service.call

      assert result[:success]
      assert_equal 1, result[:records_synced]
    end
  end

  test "returns zero records when API returns empty results" do
    stub_gaql_responses(standard: empty_response, pmax: empty_response) do
      result = service.call

      assert result[:success]
      assert_equal 0, result[:records_synced]
    end
  end

  test "maps campaign type to channel via CampaignChannelMapper" do
    stub_gaql_responses(standard: standard_response, pmax: empty_response) do
      service.call
    end

    record = account.ad_spend_records.last

    assert_equal Channels::PAID_SEARCH, record.channel
  end

  test "maps PMax campaigns by network type" do
    stub_gaql_responses(standard: empty_response, pmax: pmax_response) do
      service.call
    end

    record = account.ad_spend_records.last

    assert_equal Channels::DISPLAY, record.channel
  end

  test "stores spend_micros as bigint" do
    stub_gaql_responses(standard: standard_response, pmax: empty_response) do
      service.call
    end

    record = account.ad_spend_records.last

    assert_equal 1_500_000, record.spend_micros
  end

  test "stores hourly and device dimensions" do
    stub_gaql_responses(standard: standard_response, pmax: empty_response) do
      service.call
    end

    record = account.ad_spend_records.last

    assert_equal 14, record.spend_hour
    assert_equal "DESKTOP", record.device
  end

  test "upserts on duplicate unique key" do
    stub_gaql_responses(standard: standard_response, pmax: empty_response) do
      service.call
      fresh_service.call
    end

    assert_equal 1, account.ad_spend_records.where(platform_campaign_id: "111").count
  end

  test "increments account usage meter with records synced" do
    stub_gaql_responses(standard: standard_response, pmax: empty_response) do
      before_usage = account.current_period_usage
      service.call

      assert_equal before_usage + 1, account.current_period_usage
    end
  end

  test "combines standard and pmax results" do
    stub_gaql_responses(standard: standard_response, pmax: pmax_response) do
      assert_difference "account.ad_spend_records.count", 2 do
        service.call
      end
    end
  end

  private

  def service
    @service ||= fresh_service
  end

  def fresh_service
    AdPlatforms::Google::SpendSyncService.new(connection, date_range: Date.current..Date.current)
  end

  def account = @account ||= accounts(:one)
  def connection = @connection ||= ad_platform_connections(:google_ads)

  def standard_response
    {
      "results" => [ {
        "campaign" => { "id" => "111", "name" => "Brand Search", "advertisingChannelType" => AdPlatformChannels::SEARCH },
        "segments" => { "date" => Date.current.to_s, "hour" => 14, "device" => "DESKTOP" },
        "metrics" => { "costMicros" => "1500000", "impressions" => "100", "clicks" => "10", "conversions" => 2.0, "conversionsValue" => 99.0 },
        "customer" => { "currencyCode" => "USD" }
      } ]
    }
  end

  def pmax_response
    {
      "results" => [ {
        "campaign" => { "id" => "222", "name" => "PMax Campaign", "advertisingChannelType" => AdPlatformChannels::PERFORMANCE_MAX },
        "segments" => { "date" => Date.current.to_s, "hour" => 10, "device" => "MOBILE", "adNetworkType" => AdPlatformChannels::NETWORK_CONTENT },
        "metrics" => { "costMicros" => "2000000", "impressions" => "500", "clicks" => "25", "conversions" => 3.0, "conversionsValue" => 150.0 },
        "customer" => { "currencyCode" => "USD" }
      } ]
    }
  end

  def empty_response
    { "results" => [] }
  end

  def stub_gaql_responses(standard:, pmax:)
    call_count = 0
    responses = [ standard, pmax ]

    mock_post = lambda do |_uri, _body|
      response_body = responses[call_count] || empty_response
      call_count += 1
      build_http_response(response_body)
    end

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      Net::HTTP.stub(:start, ->(_host, _port, **_opts, &block) {
        mock_http = Object.new
        mock_http.define_singleton_method(:request) { |req| mock_post.call(req.uri, req.body) }
        block.call(mock_http)
      }) do
        yield
      end
    end
  end

  def build_http_response(body)
    resp = Net::HTTPOK.new("1.1", "200", "OK")
    json = body.to_json
    resp.define_singleton_method(:body) { json }
    resp.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess ? true : super(klass) }
    resp
  end

  def test_credentials
    { client_id: "test_client_id", client_secret: "test_client_secret", developer_token: "test_dev_token" }
  end
end
