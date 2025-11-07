require "test_helper"

class Sessions::UtmCaptureServiceTest < ActiveSupport::TestCase
  test "should extract all UTM parameters" do
    assert_equal "google", result[:utm_source]
    assert_equal "cpc", result[:utm_medium]
    assert_equal "spring_sale", result[:utm_campaign]
    assert_equal "ad_variant_a", result[:utm_content]
    assert_equal "running shoes", result[:utm_term]
  end

  test "should extract partial UTM parameters" do
    @properties = {
      "utm_source" => "facebook",
      "utm_medium" => "social"
    }

    assert_equal "facebook", result[:utm_source]
    assert_equal "social", result[:utm_medium]
    assert_nil result[:utm_campaign]
    assert_nil result[:utm_content]
    assert_nil result[:utm_term]
  end

  test "should return empty hash when no UTM parameters" do
    @properties = { "url" => "https://example.com" }

    assert_empty result
  end

  test "should handle string keys" do
    @properties = {
      "utm_source" => "twitter",
      "utm_medium" => "social"
    }

    assert_equal "twitter", result[:utm_source]
    assert_equal "social", result[:utm_medium]
  end

  test "should handle symbol keys" do
    @properties = {
      utm_source: "linkedin",
      utm_medium: "social"
    }

    assert_equal "linkedin", result[:utm_source]
    assert_equal "social", result[:utm_medium]
  end

  test "should handle mixed string and symbol keys" do
    @properties = {
      "utm_source" => "newsletter",
      utm_medium: "email"
    }

    assert_equal "newsletter", result[:utm_source]
    assert_equal "email", result[:utm_medium]
  end

  test "should ignore non-UTM properties" do
    @properties = {
      "url" => "https://example.com",
      "utm_source" => "google",
      "referrer" => "https://other.com"
    }

    assert_equal({ utm_source: "google" }, result)
  end

  test "should handle nil properties" do
    assert_empty service.call(nil)
  end

  test "should compact nil values" do
    @properties = {
      "utm_source" => "google",
      "utm_medium" => nil,
      "utm_campaign" => "sale"
    }

    refute result.key?(:utm_medium)
    assert_equal "google", result[:utm_source]
    assert_equal "sale", result[:utm_campaign]
  end

  private

  def result
    @result ||= service.call(properties)
  end

  def service
    @service ||= Sessions::UtmCaptureService.new
  end

  def properties
    @properties ||= {
      "utm_source" => "google",
      "utm_medium" => "cpc",
      "utm_campaign" => "spring_sale",
      "utm_content" => "ad_variant_a",
      "utm_term" => "running shoes"
    }
  end
end
