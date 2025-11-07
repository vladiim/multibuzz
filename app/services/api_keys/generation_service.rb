module ApiKeys
  class GenerationService
    def initialize(account, environment = :test)
      @account = account
      @environment = environment
    end

    def call(description: nil)
      plaintext_key = generate_key
      api_key = build_api_key(plaintext_key, description)

      return success_result(api_key, plaintext_key) if api_key.save

      error_result(api_key)
    end

    private

    attr_reader :account, :environment

    def generate_key
      "sk_#{environment}_#{SecureRandom.hex(16)}"
    end

    def build_api_key(plaintext_key, description)
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

    def success_result(api_key, plaintext_key)
      {
        success: true,
        api_key: api_key,
        plaintext_key: plaintext_key
      }
    end

    def error_result(api_key)
      {
        success: false,
        errors: api_key.errors.full_messages
      }
    end
  end
end
