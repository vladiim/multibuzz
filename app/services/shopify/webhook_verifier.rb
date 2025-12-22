# frozen_string_literal: true

module Shopify
  class WebhookVerifier
    def initialize(payload:, signature:, secret:)
      @payload = payload
      @signature = signature
      @secret = secret
    end

    def valid?
      return false unless signature.present?
      return false unless secret.present?

      ActiveSupport::SecurityUtils.secure_compare(computed_signature, signature)
    end

    private

    attr_reader :payload, :signature, :secret

    def computed_signature
      Base64.strict_encode64(
        OpenSSL::HMAC.digest(DIGEST_ALGORITHM, secret, payload)
      )
    end

    DIGEST_ALGORITHM = "SHA256"
    private_constant :DIGEST_ALGORITHM
  end
end
