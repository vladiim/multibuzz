# frozen_string_literal: true

require "test_helper"

class ConsentHelperTest < ActionView::TestCase
  # --- visitor_country ---

  test "visitor_country prefers CF-IPCountry header" do
    request = mock_request(headers: { "CF-IPCountry" => "FR" }, ip: "8.8.8.8")

    assert_equal "FR", visitor_country(request)
  end

  test "visitor_country uppercases CF-IPCountry value" do
    request = mock_request(headers: { "CF-IPCountry" => "de" }, ip: "8.8.8.8")

    assert_equal "DE", visitor_country(request)
  end

  test "visitor_country ignores CF-IPCountry sentinels" do
    request = mock_request(headers: { "CF-IPCountry" => "XX" }, ip: "8.8.8.8")

    assert_nil visitor_country(request)
  end

  test "visitor_country falls back to Geocoder when CF header absent" do
    Geocoder::Lookup::Test.add_stub("8.8.8.8", [ { "country_code" => "US" } ])
    request = mock_request(headers: {}, ip: "8.8.8.8")

    assert_equal "US", visitor_country(request)
  ensure
    Geocoder::Lookup::Test.reset
  end

  test "visitor_country returns nil when no header and Geocoder fails" do
    Geocoder::Lookup::Test.reset
    request = mock_request(headers: {}, ip: "0.0.0.0")

    assert_nil visitor_country(request)
  end

  # --- visitor_region ---

  test "visitor_region reads CF-Region-Code" do
    request = mock_request(headers: { "CF-Region-Code" => "CA" }, ip: "8.8.8.8")

    assert_equal "CA", visitor_region(request)
  end

  test "visitor_region returns nil when header absent" do
    request = mock_request(headers: {}, ip: "8.8.8.8")

    assert_nil visitor_region(request)
  end

  # --- requires_consent_banner? ---

  test "requires_consent_banner? true for EU member states" do
    %w[FR DE IT ES NL BE PL SE].each do |country|
      request = mock_request(headers: { "CF-IPCountry" => country }, ip: "8.8.8.8")

      assert requires_consent_banner?(request), "expected banner required for #{country}"
    end
  end

  test "requires_consent_banner? true for UK, Switzerland, Iceland, Liechtenstein, Norway" do
    %w[GB CH IS LI NO].each do |country|
      request = mock_request(headers: { "CF-IPCountry" => country }, ip: "8.8.8.8")

      assert requires_consent_banner?(request), "expected banner required for #{country}"
    end
  end

  test "requires_consent_banner? true for US visitors in California" do
    request = mock_request(headers: { "CF-IPCountry" => "US", "CF-Region-Code" => "CA" }, ip: "8.8.8.8")

    assert requires_consent_banner?(request)
  end

  test "requires_consent_banner? false for US visitors outside California" do
    request = mock_request(headers: { "CF-IPCountry" => "US", "CF-Region-Code" => "NY" }, ip: "8.8.8.8")

    refute requires_consent_banner?(request)
  end

  test "requires_consent_banner? false for non-EEA non-CA visitors" do
    %w[AU JP NZ BR IN SG].each do |country|
      request = mock_request(headers: { "CF-IPCountry" => country }, ip: "8.8.8.8")

      refute requires_consent_banner?(request), "expected banner not required for #{country}"
    end
  end

  test "requires_consent_banner? fails open when country unknown" do
    Geocoder::Lookup::Test.reset
    request = mock_request(headers: {}, ip: "0.0.0.0")

    assert requires_consent_banner?(request)
  end

  # --- consent_default_state ---

  test "consent_default_state denied when banner required" do
    request = mock_request(headers: { "CF-IPCountry" => "FR" }, ip: "8.8.8.8")

    assert_equal "denied", consent_default_state(request)
  end

  test "consent_default_state granted when banner not required" do
    request = mock_request(headers: { "CF-IPCountry" => "AU" }, ip: "8.8.8.8")

    assert_equal "granted", consent_default_state(request)
  end

  private

  def mock_request(headers:, ip:)
    Struct.new(:headers, :remote_ip).new(headers, ip)
  end
end
