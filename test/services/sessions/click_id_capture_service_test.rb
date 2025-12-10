require "test_helper"

class Sessions::ClickIdCaptureServiceTest < ActiveSupport::TestCase
  # === Google Click IDs ===

  test "captures gclid from url" do
    result = capture(url: "https://example.com?gclid=abc123")
    assert_equal "abc123", result[:gclid]
  end

  test "captures gbraid from url" do
    result = capture(url: "https://example.com?gbraid=xyz789")
    assert_equal "xyz789", result[:gbraid]
  end

  test "captures wbraid from url" do
    result = capture(url: "https://example.com?wbraid=web123")
    assert_equal "web123", result[:wbraid]
  end

  test "captures dclid from url" do
    result = capture(url: "https://example.com?dclid=dc456")
    assert_equal "dc456", result[:dclid]
  end

  # === Microsoft Click ID ===

  test "captures msclkid from url" do
    result = capture(url: "https://example.com?msclkid=ms789")
    assert_equal "ms789", result[:msclkid]
  end

  # === Meta Click ID ===

  test "captures fbclid from url" do
    result = capture(url: "https://example.com?fbclid=fb123")
    assert_equal "fb123", result[:fbclid]
  end

  # === Other Platform Click IDs ===

  test "captures ttclid from url" do
    result = capture(url: "https://example.com?ttclid=tt123")
    assert_equal "tt123", result[:ttclid]
  end

  test "captures li_fat_id from url" do
    result = capture(url: "https://example.com?li_fat_id=li123")
    assert_equal "li123", result[:li_fat_id]
  end

  test "captures twclid from url" do
    result = capture(url: "https://example.com?twclid=tw123")
    assert_equal "tw123", result[:twclid]
  end

  test "captures epik from url" do
    result = capture(url: "https://example.com?epik=pin123")
    assert_equal "pin123", result[:epik]
  end

  test "captures sclid from url" do
    result = capture(url: "https://example.com?sclid=snap123")
    assert_equal "snap123", result[:sclid]
  end

  # === Multiple Click IDs ===

  test "captures multiple click ids from same url" do
    result = capture(url: "https://example.com?gclid=g123&fbclid=f456")
    assert_equal "g123", result[:gclid]
    assert_equal "f456", result[:fbclid]
  end

  # === Properties Fallback ===

  test "captures click ids from properties if not in url" do
    result = capture(properties: { gclid: "prop123" })
    assert_equal "prop123", result[:gclid]
  end

  test "url click id takes precedence over properties" do
    result = capture(
      url: "https://example.com?gclid=url123",
      properties: { gclid: "prop123" }
    )
    assert_equal "url123", result[:gclid]
  end

  # === Edge Cases ===

  test "returns empty hash for nil url and properties" do
    assert_equal({}, capture(url: nil, properties: nil))
  end

  test "returns empty hash when no click ids present" do
    result = capture(url: "https://example.com?foo=bar")
    assert_equal({}, result)
  end

  test "ignores empty click id values" do
    result = capture(url: "https://example.com?gclid=")
    assert_equal({}, result)
  end

  test "handles invalid url gracefully" do
    result = capture(url: "not-a-valid-url", properties: { gclid: "abc" })
    assert_equal "abc", result[:gclid]
  end

  # === Source and Channel Inference ===

  test "infers source from click id" do
    assert_equal "google", infer_source(gclid: "abc")
    assert_equal "facebook", infer_source(fbclid: "abc")
    assert_equal "microsoft", infer_source(msclkid: "abc")
  end

  test "infers channel from click id" do
    assert_equal Channels::PAID_SEARCH, infer_channel(gclid: "abc")
    assert_equal Channels::PAID_SOCIAL, infer_channel(fbclid: "abc")
    assert_equal Channels::DISPLAY, infer_channel(dclid: "abc")
  end

  test "first click id wins for inference" do
    # gclid comes first in ALL array
    assert_equal "google", infer_source(fbclid: "fb", gclid: "g")
    assert_equal Channels::PAID_SEARCH, infer_channel(fbclid: "fb", gclid: "g")
  end

  private

  def capture(url: nil, properties: nil)
    Sessions::ClickIdCaptureService.new(url: url, properties: properties).call
  end

  def infer_source(click_ids)
    Sessions::ClickIdCaptureService.infer_source(click_ids)
  end

  def infer_channel(click_ids)
    Sessions::ClickIdCaptureService.infer_channel(click_ids)
  end
end
