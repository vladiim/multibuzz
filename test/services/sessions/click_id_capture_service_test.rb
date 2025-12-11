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

  test "captures ScCid (mixed case snapchat) from url" do
    result = capture(url: "https://example.com?ScCid=snap456")
    assert_equal "snap456", result[:ScCid]
  end

  # === Google Ads Source Indicator ===

  test "captures gclsrc from url" do
    result = capture(url: "https://example.com?gclsrc=aw.ds")
    assert_equal "aw.ds", result[:gclsrc]
  end

  # === Reddit Click ID ===

  test "captures rdt_cid from url" do
    result = capture(url: "https://example.com?rdt_cid=reddit123")
    assert_equal "reddit123", result[:rdt_cid]
  end

  # === Quora Click ID ===

  test "captures qclid from url" do
    result = capture(url: "https://example.com?qclid=quora123")
    assert_equal "quora123", result[:qclid]
  end

  # === Yahoo Click ID ===

  test "captures vmcid from url" do
    result = capture(url: "https://example.com?vmcid=yahoo123")
    assert_equal "yahoo123", result[:vmcid]
  end

  # === Yandex Click ID ===

  test "captures yclid from url" do
    result = capture(url: "https://example.com?yclid=yandex123")
    assert_equal "yandex123", result[:yclid]
  end

  # === Seznam Click ID ===

  test "captures sznclid from url" do
    result = capture(url: "https://example.com?sznclid=seznam123")
    assert_equal "seznam123", result[:sznclid]
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
    assert_equal "google", infer_source(gclsrc: "aw.ds")
    assert_equal "facebook", infer_source(fbclid: "abc")
    assert_equal "microsoft", infer_source(msclkid: "abc")
    assert_equal "reddit", infer_source(rdt_cid: "abc")
    assert_equal "quora", infer_source(qclid: "abc")
    assert_equal "yahoo", infer_source(vmcid: "abc")
    assert_equal "yandex", infer_source(yclid: "abc")
    assert_equal "seznam", infer_source(sznclid: "abc")
    assert_equal "snapchat", infer_source(ScCid: "abc")
  end

  test "infers channel from click id" do
    assert_equal Channels::PAID_SEARCH, infer_channel(gclid: "abc")
    assert_equal Channels::PAID_SEARCH, infer_channel(gclsrc: "aw.ds")
    assert_equal Channels::PAID_SOCIAL, infer_channel(fbclid: "abc")
    assert_equal Channels::DISPLAY, infer_channel(dclid: "abc")
    assert_equal Channels::PAID_SOCIAL, infer_channel(rdt_cid: "abc")
    assert_equal Channels::PAID_SOCIAL, infer_channel(qclid: "abc")
    assert_equal Channels::PAID_SEARCH, infer_channel(vmcid: "abc")
    assert_equal Channels::PAID_SEARCH, infer_channel(yclid: "abc")
    assert_equal Channels::PAID_SEARCH, infer_channel(sznclid: "abc")
  end

  test "first click id wins for inference" do
    # gclid comes first in ALL array
    assert_equal "google", infer_source(fbclid: "fb", gclid: "g")
    assert_equal Channels::PAID_SEARCH, infer_channel(fbclid: "fb", gclid: "g")
  end

  # === Google Places Click ID (plcid in utm_term) ===

  test "detects plcid pattern in utm_term" do
    assert ClickIdentifiers.plcid?("plcid_8067905893793481977")
    assert ClickIdentifiers.plcid?("plcid_123456")
  end

  test "rejects invalid plcid patterns" do
    refute ClickIdentifiers.plcid?("plcid_")
    refute ClickIdentifiers.plcid?("plcid_abc")
    refute ClickIdentifiers.plcid?("some_plcid_123")
    refute ClickIdentifiers.plcid?("keyword")
    refute ClickIdentifiers.plcid?(nil)
    refute ClickIdentifiers.plcid?("")
  end

  test "extracts plcid from utm_term" do
    assert_equal "plcid_8067905893793481977", ClickIdentifiers.plcid_from_utm_term("plcid_8067905893793481977")
    assert_nil ClickIdentifiers.plcid_from_utm_term("some_keyword")
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
