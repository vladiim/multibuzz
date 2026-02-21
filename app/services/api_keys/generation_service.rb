# frozen_string_literal: true

module ApiKeys
  class GenerationService < ApplicationService
    def initialize(account, environment: :test, description: nil)
      @account = account
      @environment = environment
      @description = description
    end

    private

    attr_reader :account, :environment, :description

    def run
      plaintext_key = generate_key
      api_key = build_api_key(plaintext_key)

      return error_result(api_key.errors.full_messages) unless api_key.save

      success_result(api_key: api_key, plaintext_key: plaintext_key)
    end

    def generate_key
      "sk_#{environment}_#{SecureRandom.hex(16)}"
    end

    def build_api_key(plaintext_key)
      account.api_keys.build(
        key_digest: hash_key(plaintext_key),
        key_prefix: key_prefix(plaintext_key),
        environment: environment,
        description: description
      )
    end

    def hash_key(plaintext_key)
      Digest::SHA256.hexdigest(plaintext_key)
    end

    def key_prefix(plaintext_key)
      plaintext_key[0..11]
    end
  end
end
