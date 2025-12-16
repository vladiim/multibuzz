# frozen_string_literal: true

module TestConfig
  SDK_PORTS = {
    "ruby" => 4001,
    "node" => 4002,
    "python" => 4003,
    "php" => 4004,
    "symfony" => 4005
  }.freeze

  class << self
    # Dynamically set by TestSetupHelper
    attr_accessor :api_key, :account_slug

    def api_url
      ENV.fetch("MBUZZ_API_URL", "http://localhost:3000/api/v1")
    end

    def sdk_app_url(sdk)
      port = SDK_PORTS.fetch(sdk) do
        raise "Unknown SDK: #{sdk}. Available: #{SDK_PORTS.keys.join(', ')}"
      end
      "http://localhost:#{port}"
    end

    def setup_endpoint
      "#{api_url}/test/setup"
    end

    def verification_endpoint
      "#{api_url}/test/verification"
    end
  end
end
