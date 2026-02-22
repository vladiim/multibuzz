# frozen_string_literal: true

require_relative "../test_helper"
require "httparty"

# End-to-end tests for session bot detection (bot_detection_spec.md Phase 3).
#
# Verifies that SDK middleware includes `user_agent` in the session payload
# and that the server classifies sessions correctly:
#   - Real browser UA → qualified (suspect: false)
#   - Bot UA → suspect: true, suspect_reason: "known_bot"
#   - No-signals traffic → suspect: true, suspect_reason: "no_signals"
#
# Runs against ALL server-side SDKs via the SDK env var:
#   SDK=ruby   → Sinatra test app (port 4001)
#   SDK=node   → Express test app (port 4002)
#   SDK=python → Flask test app (port 4003)
#   SDK=php    → Vanilla PHP test app (port 4004)
#
# Before the fix: user_agent is NOT sent in session payload → all tests FAIL
# After the fix: user_agent is included → all tests PASS
class BotDetectionTest < Minitest::Test # rubocop:disable Metrics/ClassLength
  REAL_BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  BOT_UA = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

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
  # Core: middleware sends user_agent in session payload
  # -------------------------------------------------------------------

  def test_session_stores_user_agent_from_middleware
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_navigation_request(user_agent: REAL_BROWSER_UA)
    data = poll_for_visitor(visitor_id)

    refute_nil data[:visitor], "Visitor should be created"
    refute_empty data[:sessions], "Session should be created"

    session = data[:sessions].first

    assert_equal REAL_BROWSER_UA, session[:user_agent],
      "Session should store the user_agent sent by SDK middleware"
  end

  # -------------------------------------------------------------------
  # Bot classification: known bot UA → suspect with known_bot reason
  # -------------------------------------------------------------------

  def test_bot_user_agent_classified_as_known_bot
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_navigation_request(user_agent: BOT_UA)
    session = first_session_for(visitor_id)

    assert_equal BOT_UA, session[:user_agent], "Bot user_agent should be stored on session"
    assert session[:suspect], "Bot session should be marked suspect"
    assert_equal "known_bot", session[:suspect_reason], "Bot suspect_reason should be 'known_bot'"
  end

  # -------------------------------------------------------------------
  # Real browser: qualified session (not suspect)
  # -------------------------------------------------------------------

  def test_real_browser_with_utm_is_qualified
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_navigation_request(
      user_agent: REAL_BROWSER_UA,
      path: "/?utm_source=google&utm_medium=cpc"
    )
    session = first_session_for(visitor_id)

    assert_equal REAL_BROWSER_UA, session[:user_agent], "Real browser user_agent should be stored"
    refute session[:suspect], "Real browser with UTM signals should NOT be suspect"
    assert_nil session[:suspect_reason], "Qualified session should have nil suspect_reason"
  end

  # -------------------------------------------------------------------
  # Bot with UTM: bot detection takes priority over signals
  # -------------------------------------------------------------------

  def test_bot_with_utm_still_classified_as_bot
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_navigation_request(
      user_agent: BOT_UA,
      path: "/?utm_source=google&gclid=abc123"
    )
    session = first_session_for(visitor_id)

    assert session[:suspect], "Bot with UTM signals should still be suspect"
    assert_equal "known_bot", session[:suspect_reason], "Bot detection should take priority"
  end

  # -------------------------------------------------------------------
  # No signals: real browser with no referrer/UTM → no_signals
  # -------------------------------------------------------------------

  def test_real_browser_no_signals_classified_as_no_signals
    skip "Requires local servers" unless servers_available?
    skip_unless_auto_visitor!

    visitor_id, _cookies = make_navigation_request(user_agent: REAL_BROWSER_UA, path: "/")
    session = first_session_for(visitor_id)

    assert session[:suspect], "Real browser with no signals should be suspect"
    assert_equal "no_signals", session[:suspect_reason], "Should classify as 'no_signals'"
  end

  # -------------------------------------------------------------------
  # PHP cookie-first variants
  # -------------------------------------------------------------------

  def test_php_session_stores_user_agent
    skip "Requires local servers" unless servers_available?
    skip_unless_cookie_first!

    visitor_id = SecureRandom.hex(32)
    make_request_with_visitor_cookie(visitor_id, user_agent: REAL_BROWSER_UA)
    session = first_session_for(visitor_id)

    assert_equal REAL_BROWSER_UA, session[:user_agent], "PHP SDK should store user_agent"
  end

  def test_php_bot_detection
    skip "Requires local servers" unless servers_available?
    skip_unless_cookie_first!

    visitor_id = SecureRandom.hex(32)
    make_request_with_visitor_cookie(visitor_id, user_agent: BOT_UA)
    session = first_session_for(visitor_id)

    assert session[:suspect], "Bot session should be marked suspect"
    assert_equal "known_bot", session[:suspect_reason], "Bot should be classified as known_bot"
  end

  private

  def created_visitor_ids
    @created_visitor_ids ||= []
  end

  SDKS_WITH_AUTO_VISITOR = %w[ruby node python].freeze
  SDKS_COOKIE_FIRST = %w[php symfony].freeze

  def auto_generates_visitor?
    SDKS_WITH_AUTO_VISITOR.include?(@sdk)
  end

  def cookie_first_sdk?
    SDKS_COOKIE_FIRST.include?(@sdk)
  end

  def skip_unless_auto_visitor!
    skip "#{@sdk} SDK does not auto-generate visitor IDs" unless auto_generates_visitor?
  end

  def skip_unless_cookie_first!
    skip "#{@sdk} SDK auto-generates visitor IDs" unless cookie_first_sdk?
  end

  def first_session_for(visitor_id)
    data = poll_for_visitor(visitor_id)

    refute_empty data[:sessions], "Session should be created"
    data[:sessions].first
  end

  # Make a page navigation request (Sec-Fetch-* navigate + document)
  def make_navigation_request(user_agent:, path: "/") # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    uri = URI.parse("#{sdk_app_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = user_agent
    request["Accept"] = "text/html"
    request["Sec-Fetch-Mode"] = "navigate"
    request["Sec-Fetch-Dest"] = "document"
    request["Sec-Fetch-Site"] = "none"
    request["Sec-Fetch-User"] = "?1"

    response = http.request(request)
    cookies = response.get_fields("Set-Cookie") || []

    visitor_id = extract_cookie(cookies, "_mbuzz_vid")
    created_visitor_ids << visitor_id if visitor_id

    [ visitor_id, cookies ]
  end

  # Make request with pre-set visitor cookie (PHP/Symfony pattern)
  def make_request_with_visitor_cookie(visitor_id, user_agent:)
    uri = URI.parse("#{sdk_app_url}/")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Get.new(uri.path)
    request["User-Agent"] = user_agent
    request["Accept"] = "text/html"
    request["Cookie"] = "_mbuzz_vid=#{visitor_id}"
    request["Sec-Fetch-Mode"] = "navigate"
    request["Sec-Fetch-Dest"] = "document"
    request["Sec-Fetch-Site"] = "none"

    http.request(request)
    created_visitor_ids << visitor_id
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

  POLL_INITIAL_WAIT = 3
  POLL_ATTEMPTS = 15
  POLL_INTERVAL = 1

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
