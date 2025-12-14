require "test_helper"

class Sessions::UrlNormalizationServiceTest < ActiveSupport::TestCase
  # === Protocol Normalization ===

  test "strips protocol" do
    assert_equal "example.com/page", normalize("https://example.com/page")
    assert_equal "example.com/page", normalize("http://example.com/page")
  end

  # === WWW Normalization ===

  test "strips www prefix" do
    assert_equal "example.com", normalize("https://www.example.com")
    assert_equal "example.com/page", normalize("http://www.example.com/page")
  end

  # === Trailing Slash ===

  test "strips trailing slash" do
    assert_equal "example.com", normalize("https://example.com/")
    assert_equal "example.com/page", normalize("https://example.com/page/")
  end

  # === Query String Handling ===

  test "preserves query strings by default" do
    assert_equal "example.com/page?foo=bar", normalize("https://example.com/page?foo=bar")
  end

  test "strips query strings when configured" do
    assert_equal "example.com/page", normalize("https://example.com/page?foo=bar", strip_query: true)
  end

  # === Fragment Handling ===

  test "strips fragments" do
    assert_equal "example.com/page", normalize("https://example.com/page#section")
    assert_equal "example.com/page?foo=bar", normalize("https://example.com/page?foo=bar#section")
  end

  # === Case Normalization ===

  test "lowercases hostname" do
    assert_equal "example.com/Page", normalize("https://EXAMPLE.COM/Page")
  end

  test "preserves path case" do
    assert_equal "example.com/CamelCase", normalize("https://example.com/CamelCase")
  end

  # === Combined Normalization ===

  test "handles complex urls" do
    url = "HTTPS://WWW.EXAMPLE.COM/Page/SubPage/?utm_source=fb#anchor"
    assert_equal "example.com/Page/SubPage?utm_source=fb", normalize(url)
  end

  # === Edge Cases ===

  test "handles nil" do
    assert_nil normalize(nil)
  end

  test "handles blank" do
    assert_nil normalize("")
    assert_nil normalize("   ")
  end

  test "handles invalid urls gracefully" do
    assert_equal "not-a-url", normalize("not-a-url")
  end

  test "handles localhost" do
    assert_equal "localhost:3000/page", normalize("http://localhost:3000/page")
  end

  test "handles ip addresses" do
    assert_equal "192.168.1.1:8080/api", normalize("http://192.168.1.1:8080/api")
  end

  private

  def normalize(url, **options)
    Sessions::UrlNormalizationService.call(url, **options)
  end
end
