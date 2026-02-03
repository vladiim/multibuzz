# frozen_string_literal: true

require_relative "../test_helper"
require "httparty"

# End-to-end tests for navigation-aware session creation (Sec-Fetch-* whitelist)
#
# These tests verify that SDK middleware only creates sessions for real page
# navigations, filtering out Turbo frames, htmx partials, fetch/XHR, and
# prefetch requests. Uses browser-enforced Sec-Fetch-* headers as the primary
# signal, with a framework-specific blacklist fallback for old browsers.
#
# Runs against ALL server-side SDKs via the SDK env var:
#   SDK=ruby  → Sinatra test app (port 4001) — same Rack middleware as Rails
#   SDK=node  → Express test app (port 4002)
#   SDK=python → Flask test app (port 4003)
#   SDK=php   → Vanilla PHP test app (port 4004)
#   SDK=symfony → Symfony test app (port 4005)
#
# Spec: lib/specs/navigation_aware_session_creation_spec.md
#
# Before the fix: ALL tests except the "creates session" ones FAIL because
# the middleware creates sessions for every request regardless of headers.
# After the fix: ALL tests PASS.
class NavigationDetectionTest < Minitest::Test
  def setup
    @sdk = ENV.fetch("SDK", "ruby")
  end

  def teardown
    @created_visitor_ids&.each do |vid|
      VerificationHelper.cleanup(visitor_id: vid)
    rescue StandardError
      nil
    end
  end

  # -------------------------------------------------------------------
  # Whitelist path: modern browsers with Sec-Fetch-* headers
  # -------------------------------------------------------------------

  def test_real_page_navigation_creates_session
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_request(
      "Sec-Fetch-Mode" => "navigate",
      "Sec-Fetch-Dest" => "document",
      "Sec-Fetch-Site" => "none",
      "Sec-Fetch-User" => "?1"
    )

    data = poll_for_visitor(visitor_id)

    refute_nil data, "Visitor should exist"
    refute_nil data[:visitor], "Visitor record should be created"
    refute_empty data[:sessions],
      "Real page navigation (navigate + document) MUST create a session"
  end

  def test_turbo_frame_request_skips_session
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_request(
      "Sec-Fetch-Mode" => "same-origin",
      "Sec-Fetch-Dest" => "empty",
      "Sec-Fetch-Site" => "same-origin",
      "Turbo-Frame" => "content_frame"
    )

    wait_for_async
    data = verify_once(visitor_id)

    assert_no_sessions data,
      "Turbo frame request (same-origin + empty) must NOT create a session"
  end

  def test_htmx_request_skips_session
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_request(
      "Sec-Fetch-Mode" => "same-origin",
      "Sec-Fetch-Dest" => "empty",
      "Sec-Fetch-Site" => "same-origin",
      "HX-Request" => "true",
      "HX-Target" => "content"
    )

    wait_for_async
    data = verify_once(visitor_id)

    assert_no_sessions data,
      "htmx request (HX-Request header) must NOT create a session"
  end

  def test_fetch_xhr_skips_session
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_request(
      "Sec-Fetch-Mode" => "cors",
      "Sec-Fetch-Dest" => "empty",
      "Sec-Fetch-Site" => "same-origin"
    )

    wait_for_async
    data = verify_once(visitor_id)

    assert_no_sessions data,
      "fetch/XHR request (cors + empty) must NOT create a session"
  end

  def test_prefetch_skips_session
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_request(
      "Sec-Fetch-Mode" => "navigate",
      "Sec-Fetch-Dest" => "document",
      "Sec-Fetch-Site" => "same-origin",
      "Sec-Purpose" => "prefetch"
    )

    wait_for_async
    data = verify_once(visitor_id)

    assert_no_sessions data,
      "Prefetch (navigate + document + Sec-Purpose: prefetch) must NOT create a session"
  end

  def test_same_origin_empty_skips_session
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    # Generic sub-request pattern (Unpoly, Livewire, any JS framework)
    visitor_id, _cookies = make_request(
      "Sec-Fetch-Mode" => "same-origin",
      "Sec-Fetch-Dest" => "empty",
      "Sec-Fetch-Site" => "same-origin"
    )

    wait_for_async
    data = verify_once(visitor_id)

    assert_no_sessions data,
      "Generic sub-request (same-origin + empty) must NOT create a session"
  end

  def test_iframe_navigation_skips_session
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_request(
      "Sec-Fetch-Mode" => "navigate",
      "Sec-Fetch-Dest" => "iframe",
      "Sec-Fetch-Site" => "same-origin"
    )

    wait_for_async
    data = verify_once(visitor_id)

    assert_no_sessions data,
      "iframe navigation (navigate + iframe) must NOT create a session"
  end

  # -------------------------------------------------------------------
  # Blacklist fallback: old browsers without Sec-Fetch-* headers
  # -------------------------------------------------------------------

  def test_old_browser_without_framework_headers_creates_session
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    # No Sec-Fetch headers, no framework headers — legacy browser doing a
    # real page load. Fallback should allow session creation.
    visitor_id, _cookies = make_request({})

    data = poll_for_visitor(visitor_id)

    refute_nil data, "Visitor should exist"
    refute_empty data[:sessions],
      "Old browser with no framework headers MUST create a session (fallback)"
  end

  def test_old_browser_with_turbo_frame_header_skips_session
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    # No Sec-Fetch headers but Turbo-Frame present — blacklist catches it
    visitor_id, _cookies = make_request(
      "Turbo-Frame" => "lazy_banner"
    )

    wait_for_async
    data = verify_once(visitor_id)

    assert_no_sessions data,
      "Old browser with Turbo-Frame header must NOT create a session (blacklist fallback)"
  end

  def test_old_browser_with_hx_request_header_skips_session
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_request(
      "HX-Request" => "true"
    )

    wait_for_async
    data = verify_once(visitor_id)

    assert_no_sessions data,
      "Old browser with HX-Request header must NOT create a session (blacklist fallback)"
  end

  def test_old_browser_with_xhr_header_skips_session
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_request(
      "X-Requested-With" => "XMLHttpRequest"
    )

    wait_for_async
    data = verify_once(visitor_id)

    assert_no_sessions data,
      "Old browser with X-Requested-With: XMLHttpRequest must NOT create a session (blacklist)"
  end

  def test_old_browser_with_unpoly_header_skips_session
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_request(
      "X-Up-Version" => "3.0.0"
    )

    wait_for_async
    data = verify_once(visitor_id)

    assert_no_sessions data,
      "Old browser with X-Up-Version (Unpoly) must NOT create a session (blacklist)"
  end

  # -------------------------------------------------------------------
  # Visitor cookie: ALWAYS set regardless of navigation detection
  # -------------------------------------------------------------------

  def test_visitor_cookie_set_on_real_navigation
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    _visitor_id, cookies = make_request(
      "Sec-Fetch-Mode" => "navigate",
      "Sec-Fetch-Dest" => "document"
    )

    assert_visitor_cookie_present cookies,
      "Visitor cookie must be set on real navigation"
  end

  def test_visitor_cookie_set_on_turbo_frame
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    _visitor_id, cookies = make_request(
      "Sec-Fetch-Mode" => "same-origin",
      "Sec-Fetch-Dest" => "empty",
      "Turbo-Frame" => "content_frame"
    )

    assert_visitor_cookie_present cookies,
      "Visitor cookie must be set even on Turbo frame requests (only session creation is gated)"
  end

  def test_visitor_cookie_set_on_xhr
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    _visitor_id, cookies = make_request(
      "Sec-Fetch-Mode" => "cors",
      "Sec-Fetch-Dest" => "empty"
    )

    assert_visitor_cookie_present cookies,
      "Visitor cookie must be set even on XHR requests (only session creation is gated)"
  end

  # -------------------------------------------------------------------
  # Session cookie: should NOT be set (v0.7.0+ migration)
  # -------------------------------------------------------------------

  def test_session_cookie_not_set
    skip "Requires local servers" unless servers_available?
    skip "Ruby SDK only — other SDKs already removed _mbuzz_sid" unless @sdk == "ruby"

    _visitor_id, cookies = make_request(
      "Sec-Fetch-Mode" => "navigate",
      "Sec-Fetch-Dest" => "document"
    )

    session_cookie = extract_cookie(cookies, "_mbuzz_sid")
    assert_nil session_cookie,
      "Session cookie (_mbuzz_sid) must NOT be set — removed in v0.8.0"
  end

  # -------------------------------------------------------------------
  # Concurrent sub-requests: the inflation scenario
  # -------------------------------------------------------------------

  def test_concurrent_turbo_frames_do_not_inflate_visits
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    # Simulate a first page load with 5 concurrent requests:
    # 1 real navigation + 4 Turbo frame sub-requests
    # Each is a fresh request (no cookies) — worst case scenario
    navigation_vid, _nav_cookies = make_request(
      "Sec-Fetch-Mode" => "navigate",
      "Sec-Fetch-Dest" => "document"
    )

    # 4 Turbo frame requests (simulating lazy-loaded frames on same page)
    frame_vids = 4.times.map do
      vid, _cookies = make_request(
        "Sec-Fetch-Mode" => "same-origin",
        "Sec-Fetch-Dest" => "empty",
        "Turbo-Frame" => "frame_#{SecureRandom.hex(4)}"
      )
      vid
    end

    # Only the navigation request should have created a session
    nav_data = poll_for_visitor(navigation_vid)
    refute_empty nav_data[:sessions],
      "Navigation request must create a session"

    # Frame requests should NOT have sessions (single-shot check — no session was created)
    frame_vids.compact.each do |fvid|
      frame_data = verify_once(fvid)
      assert_no_sessions frame_data,
        "Turbo frame sub-request must NOT create a session (visitor #{fvid})"
    end
  end

  private

  def created_visitor_ids
    @created_visitor_ids ||= []
  end

  # SDKs that auto-generate visitor IDs in middleware (cookie set on first request).
  # PHP/Symfony read cookies but don't generate — visitor_id is nil without a cookie.
  SDKS_WITH_AUTO_VISITOR = %w[ruby node python].freeze

  def auto_generates_visitor?
    SDKS_WITH_AUTO_VISITOR.include?(@sdk)
  end

  def skip_unless_auto_visitor!
    skip "#{@sdk} SDK does not auto-generate visitor IDs in middleware" unless auto_generates_visitor?
  end

  # Make an HTTP request to the SDK test app with specific headers.
  # Returns [visitor_id, response_cookies] where visitor_id is extracted
  # from the Set-Cookie header.
  #
  # Each request uses a unique User-Agent to produce a unique device_fingerprint
  # on the server (SHA256 of ip|user_agent). Without this, the server's
  # deduplication logic merges all requests into one canonical visitor (same
  # fingerprint within 30s window), causing poll_for_visitor to look up a
  # visitor_id that was never persisted.
  def make_request(extra_headers)
    uri = URI.parse("#{sdk_app_url}/")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Get.new(uri.path)
    request["User-Agent"] = "NavigationDetectionTest/1.0 (req-#{SecureRandom.hex(8)})"
    request["Accept"] = "text/html"

    extra_headers.each { |k, v| request[k] = v }

    response = http.request(request)
    cookies = response.get_fields("Set-Cookie") || []

    visitor_id = extract_cookie(cookies, "_mbuzz_vid")
    created_visitor_ids << visitor_id if visitor_id

    [visitor_id, cookies]
  end

  def extract_cookie(cookies, name)
    cookies.each do |cookie_str|
      if cookie_str.start_with?("#{name}=")
        value = cookie_str.split("=", 2).last.split(";").first
        return value unless value.empty?
      end
    end
    nil
  end

  # Single-shot verification — no polling. Used by "no sessions" tests where the
  # middleware should NOT have spawned a background thread (no visitor to find).
  def verify_once(visitor_id)
    return { sessions: [] } unless visitor_id

    VerificationHelper.verify(visitor_id: visitor_id) || { sessions: [] }
  end

  # Poll verification until visitor record exists. Used by "creates session" tests
  # where the middleware spawns a background thread that calls the API asynchronously.
  # Initial wait gives the background thread time to complete its HTTP call;
  # subsequent polls handle API processing latency.
  POLL_INITIAL_WAIT = 3
  POLL_ATTEMPTS = 15
  POLL_INTERVAL = 1

  def poll_for_visitor(visitor_id)
    return { sessions: [] } unless visitor_id

    sleep POLL_INITIAL_WAIT

    POLL_ATTEMPTS.times do |i|
      data = VerificationHelper.verify(visitor_id: visitor_id) || {}
      return data if data[:visitor] && data[:visitor][:visitor_id]

      sleep POLL_INTERVAL unless i == POLL_ATTEMPTS - 1
    end

    { sessions: [] }
  end

  # Brief pause for async processing — used before verify_once to give any
  # (unexpected) background threads time to complete.
  def wait_for_async
    sleep 3
  end

  def assert_no_sessions(data, message)
    sessions = data[:sessions] || []
    assert_empty sessions, message
  end

  def assert_visitor_cookie_present(cookies, message)
    visitor_id = extract_cookie(cookies, "_mbuzz_vid")
    refute_nil visitor_id, message
    assert_match(/\A[a-f0-9]{64}\z/, visitor_id,
      "Visitor cookie should be a 64-char hex string, got: #{visitor_id.inspect}")
  end

  def sdk_app_url
    TestConfig.sdk_app_url(@sdk)
  end

  def servers_available?
    HTTParty.get("#{TestConfig.api_url}/health")
    Net::HTTP.get(URI.parse("#{sdk_app_url}/api/ids"))
    true
  rescue StandardError
    false
  end
end
