require "test_helper"

class Sessions::UtmNormalizationServiceTest < ActiveSupport::TestCase
  # === Source Normalization ===

  test "normalizes source aliases" do
    assert_equal "facebook", normalize_source("fb")
    assert_equal "facebook", normalize_source("FB")
    assert_equal "instagram", normalize_source("ig")
    assert_equal "twitter", normalize_source("tw")
    assert_equal "twitter", normalize_source("x")
    assert_equal "linkedin", normalize_source("li")
    assert_equal "youtube", normalize_source("yt")
    assert_equal "google", normalize_source("goog")
    assert_equal "microsoft", normalize_source("bing")
    assert_equal "microsoft", normalize_source("msn")
  end

  test "preserves canonical source names" do
    assert_equal "facebook", normalize_source("facebook")
    assert_equal "google", normalize_source("google")
    assert_equal "twitter", normalize_source("twitter")
  end

  test "lowercases source values" do
    assert_equal "facebook", normalize_source("Facebook")
    assert_equal "facebook", normalize_source("FACEBOOK")
  end

  test "handles source typos with levenshtein" do
    assert_equal "facebook", normalize_source("facebok")
    assert_equal "facebook", normalize_source("facbook")
    assert_equal "instagram", normalize_source("instagam")
    assert_equal "linkedin", normalize_source("linkedn")
  end

  test "does not match sources beyond levenshtein threshold" do
    # Distance > 2, should return as-is (lowercase)
    assert_equal "facbk", normalize_source("facbk")  # distance 3
  end

  test "returns unknown sources as-is lowercase" do
    assert_equal "chatgpt.com", normalize_source("chatgpt.com")
    assert_equal "somesite", normalize_source("SomeSite")
  end

  # === Medium Normalization ===

  test "normalizes medium to canonical form" do
    # paid_search variations
    assert_equal "cpc", normalize_medium("cpc")
    assert_equal "cpc", normalize_medium("CPC")
    assert_equal "cpc", normalize_medium("ppc")
    assert_equal "cpc", normalize_medium("paidsearch")
    assert_equal "cpc", normalize_medium("paid-search")
    assert_equal "cpc", normalize_medium("paid_search")
    assert_equal "cpc", normalize_medium("sem")
    assert_equal "cpc", normalize_medium("adwords")
  end

  test "normalizes paid_social variations" do
    assert_equal "paid_social", normalize_medium("paid_social")
    assert_equal "paid_social", normalize_medium("paid-social")
    assert_equal "paid_social", normalize_medium("paidsocial")
    assert_equal "paid_social", normalize_medium("cpm-social")
    assert_equal "paid_social", normalize_medium("cpm_social")
  end

  test "normalizes social variations" do
    assert_equal "social", normalize_medium("social")
    assert_equal "social", normalize_medium("social-media")
    assert_equal "social", normalize_medium("social_media")
    assert_equal "social", normalize_medium("sm")
  end

  test "normalizes email variations" do
    assert_equal "email", normalize_medium("email")
    assert_equal "email", normalize_medium("e-mail")
    assert_equal "email", normalize_medium("e_mail")
    assert_equal "email", normalize_medium("newsletter")
  end

  test "normalizes display variations" do
    assert_equal "display", normalize_medium("display")
    assert_equal "display", normalize_medium("banner")
    assert_equal "display", normalize_medium("gdn")
    assert_equal "display", normalize_medium("programmatic")
  end

  test "normalizes video variations" do
    assert_equal "video", normalize_medium("video")
    assert_equal "video", normalize_medium("cpv")
  end

  test "normalizes affiliate variations" do
    assert_equal "affiliate", normalize_medium("affiliate")
    assert_equal "affiliate", normalize_medium("affiliates")
    assert_equal "affiliate", normalize_medium("partner")
  end

  test "preserves organic medium" do
    assert_equal "organic", normalize_medium("organic")
    assert_equal "organic", normalize_medium("Organic")
  end

  test "preserves referral medium" do
    assert_equal "referral", normalize_medium("referral")
  end

  test "does NOT use levenshtein for mediums" do
    # cpp vs cpc is distance 1, but should NOT match (no fuzzy matching for mediums)
    assert_equal "cpp", normalize_medium("cpp")
  end

  test "returns unknown mediums as-is lowercase" do
    assert_equal "rss", normalize_medium("rss")
    assert_equal "unknown", normalize_medium("Unknown")
  end

  # === Separator Normalization ===

  test "normalizes separators to underscores" do
    assert_equal "paid_social", normalize_medium("paid-social")
    assert_equal "paid_social", normalize_medium("paid social")
    # social-media → social_media → social (alias lookup)
    assert_equal "social", normalize_medium("social-media")
  end

  # === Compound Word Detection ===

  test "detects compound words without separators" do
    assert_equal "paid_social", normalize_medium("paidsocial")
    assert_equal "cpc", normalize_medium("paidsearch")
  end

  # === Full UTM Hash Normalization ===

  test "normalizes full utm hash" do
    utm = {
      utm_source: "FB",
      utm_medium: "paid-social",
      utm_campaign: "BlackFriday2025",
      utm_content: "ad_123",
      utm_term: "dog hotel"
    }

    result = service(utm).call

    assert_equal "facebook", result[:utm_source]
    assert_equal "paid_social", result[:utm_medium]
    assert_equal "blackfriday2025", result[:utm_campaign]
    assert_equal "ad_123", result[:utm_content]
    assert_equal "dog hotel", result[:utm_term]
  end

  test "handles empty utm hash" do
    assert_equal({}, service({}).call)
  end

  test "handles nil utm hash" do
    assert_equal({}, service(nil).call)
  end

  test "preserves original keys as symbols" do
    utm = { "utm_source" => "fb", "utm_medium" => "cpc" }
    result = service(utm).call

    assert_equal "facebook", result[:utm_source]
    assert_equal "cpc", result[:utm_medium]
  end

  private

  def service(utm)
    Sessions::UtmNormalizationService.new(utm)
  end

  def normalize_source(value)
    Sessions::UtmNormalizationService.normalize_source(value)
  end

  def normalize_medium(value)
    Sessions::UtmNormalizationService.normalize_medium(value)
  end
end
