# frozen_string_literal: true

require "test_helper"

module Shopify
  class WebhookVerifierTest < ActiveSupport::TestCase
    test "returns true for valid signature" do
      assert_predicate verifier(signature: valid_signature), :valid?
    end

    test "returns false for invalid signature" do
      refute_predicate verifier(signature: "invalid_signature"), :valid?
    end

    test "returns false when signature is nil" do
      refute_predicate verifier(signature: nil), :valid?
    end

    test "returns false when signature is blank" do
      refute_predicate verifier(signature: ""), :valid?
    end

    test "returns false when secret is nil" do
      refute_predicate verifier(secret: nil), :valid?
    end

    test "returns false when secret is blank" do
      refute_predicate verifier(secret: ""), :valid?
    end

    private

    def payload
      @payload ||= '{"id":123,"total_price":"99.99"}'
    end

    def secret
      @secret ||= "shpss_test_webhook_secret"
    end

    def valid_signature
      Base64.strict_encode64(
        OpenSSL::HMAC.digest("SHA256", secret, payload)
      )
    end

    def verifier(payload: self.payload, signature: valid_signature, secret: self.secret)
      WebhookVerifier.new(payload: payload, signature: signature, secret: secret)
    end
  end
end
