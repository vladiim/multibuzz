# frozen_string_literal: true

require "securerandom"
require "net/http"
require "uri"
require "json"
require "minitest/autorun"
require "capybara/minitest"
require "capybara-playwright-driver"
require_relative "helpers/test_config"
require_relative "helpers/test_setup_helper"
require_relative "helpers/verification_helper"

# Load API key from env file if not already set
# (Created by TestSetupHelper.setup! in Rakefile)
env_file = File.expand_path("../.test_env", __FILE__)
if File.exist?(env_file)
  File.readlines(env_file).each do |line|
    key, value = line.strip.split("=", 2)
    next unless key && value
    case key
    when "MBUZZ_API_KEY"
      TestConfig.api_key = value
    when "MBUZZ_ACCOUNT_SLUG"
      TestConfig.account_slug = value
    end
  end
end

# Playwright setup
Capybara.register_driver :playwright do |app|
  Capybara::Playwright::Driver.new(
    app,
    browser_type: :chromium,
    headless: ENV.fetch("HEADLESS", "true") == "true"
  )
end

Capybara.default_driver = :playwright
Capybara.javascript_driver = :playwright

# Base test class for SDK integration tests
class SdkIntegrationTest < Minitest::Test
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  # Compatibility helpers for Rails-like assertions
  def assert_not_nil(obj, msg = nil)
    refute_nil obj, msg
  end

  def setup
    Capybara.app_host = sdk_app_url
    Capybara.reset_sessions!
    @visitor_id = nil
  end

  def teardown
    cleanup_test_data if @visitor_id
    Capybara.reset_sessions!
  end

  private

  def sdk
    ENV.fetch("SDK", "ruby")
  end

  def sdk_app_url
    TestConfig.sdk_app_url(sdk)
  end

  # Get current visitor ID from the test app UI
  def current_visitor_id
    find("#visitor-id", wait: 5).text
  rescue Capybara::ElementNotFound
    nil
  end

  # Get current session ID from the test app UI
  def current_session_id
    find("#session-id", wait: 5).text
  rescue Capybara::ElementNotFound
    nil
  end

  # Verify test data via the verification endpoint
  def verify_test_data(visitor_id: nil, user_id: nil)
    VerificationHelper.verify(
      visitor_id: visitor_id || @visitor_id,
      user_id: user_id
    )
  end

  # Wait for async session creation by polling until visitor exists.
  # Falls back to a simple sleep when no visitor_id is tracked.
  ASYNC_POLL_ATTEMPTS = 8
  ASYNC_POLL_INTERVAL = 1

  def wait_for_async(seconds = 2)
    return sleep(seconds) unless @visitor_id

    poll_until_visitor_exists(@visitor_id, seconds)
  end

  def poll_until_visitor_exists(visitor_id, min_wait)
    sleep min_wait

    ASYNC_POLL_ATTEMPTS.times do |i|
      data = VerificationHelper.verify(visitor_id: visitor_id)
      return if data&.dig(:visitor, :visitor_id)

      sleep ASYNC_POLL_INTERVAL unless i == ASYNC_POLL_ATTEMPTS - 1
    end
  end

  # Clean up test data after the test
  def cleanup_test_data
    VerificationHelper.cleanup(visitor_id: @visitor_id) if @visitor_id
  end

  # Track visitor ID for cleanup
  def track_visitor_id!
    @visitor_id = current_visitor_id
  end

  # Create a session via the API to register the visitor
  # Visitors must exist before events can be tracked (require_existing_visitor spec)
  # @param visitor_id [String] The visitor ID to register
  # @param url [String] Optional URL for the session (defaults to test app URL)
  # @param referrer [String] Optional referrer URL
  # @return [Hash] The session creation result
  def create_session_for_visitor(visitor_id, url: nil, referrer: nil)
    session_id = SecureRandom.hex(32)
    uri = URI.parse("#{TestConfig.api_url}/sessions")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{TestConfig.api_key}"

    session_data = {
      visitor_id: visitor_id,
      session_id: session_id,
      url: url || "#{sdk_app_url}/",
      started_at: Time.now.utc.iso8601
    }
    session_data[:referrer] = referrer if referrer

    request.body = { session: session_data }.to_json

    response = http.request(request)
    result = JSON.parse(response.body)
    @session_id = result["session_id"] if result["status"] == "accepted"
    result
  rescue => e
    { "status" => "error", "error" => e.message }
  end

  # Helper to visit page and register visitor in one call
  # This is the standard pattern for tests that need a registered visitor
  def visit_and_register(path = "/", url: nil, referrer: nil)
    visit path
    track_visitor_id!
    result = create_session_for_visitor(@visitor_id, url: url, referrer: referrer)
    raise "Session creation failed: #{result.inspect}" unless result["status"] == "accepted"
    wait_for_async(0.5)
    result
  end
end
