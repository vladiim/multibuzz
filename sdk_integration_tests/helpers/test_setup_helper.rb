# frozen_string_literal: true

require "httparty"
require_relative "test_config"

module TestSetupHelper
  class SetupError < StandardError; end

  class << self
    # Create a test account and API key for the test run
    # Call this once at the start of the test suite
    def setup!
      puts "Creating test account and API key..."

      response = HTTParty.post(
        TestConfig.setup_endpoint,
        headers: { "Content-Type" => "application/json" }
      )

      unless response.success?
        raise SetupError, "Failed to create test account: #{response.body}"
      end

      data = response.parsed_response
      TestConfig.api_key = data["api_key"]
      TestConfig.account_slug = data["account_slug"]

      puts "Test account created: #{TestConfig.account_slug}"
      puts "API key: #{TestConfig.api_key[0..15]}..."

      # Write to temp file so test apps can read it
      write_env_file

      TestConfig.api_key
    end

    # Tear down the test account after the test run
    # Call this at the end of the test suite
    def teardown!
      return unless TestConfig.account_slug

      puts "Cleaning up test account: #{TestConfig.account_slug}..."

      response = HTTParty.delete(
        TestConfig.setup_endpoint,
        query: { account_slug: TestConfig.account_slug },
        headers: { "Content-Type" => "application/json" }
      )

      if response.success?
        puts "Test account deleted."
      else
        puts "Warning: Failed to delete test account: #{response.body}"
      end

      # Clean up temp file
      cleanup_env_file

      TestConfig.api_key = nil
      TestConfig.account_slug = nil
    end

    private

    def env_file_path
      File.expand_path("../../.test_env", __FILE__)
    end

    def write_env_file
      File.write(env_file_path, <<~ENV)
        MBUZZ_API_KEY=#{TestConfig.api_key}
        MBUZZ_API_URL=#{TestConfig.api_url}
        MBUZZ_ACCOUNT_SLUG=#{TestConfig.account_slug}
      ENV
    end

    def cleanup_env_file
      File.delete(env_file_path) if File.exist?(env_file_path)
    end
  end
end
