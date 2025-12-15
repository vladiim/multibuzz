# frozen_string_literal: true

require "securerandom"
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

  # Wait for async operations to complete
  def wait_for_async(seconds = 2)
    sleep seconds
  end

  # Clean up test data after the test
  def cleanup_test_data
    VerificationHelper.cleanup(visitor_id: @visitor_id) if @visitor_id
  end

  # Track visitor ID for cleanup
  def track_visitor_id!
    @visitor_id = current_visitor_id
  end
end
