require "test_helper"

class ApiKeys::GenerationServiceTest < ActiveSupport::TestCase
    test "should generate test API key" do
      result = service(:test).call

      assert result[:success]
      assert_instance_of ApiKey, result[:api_key]
      assert result[:plaintext_key].start_with?("sk_test_")
      assert_equal 40, result[:plaintext_key].length  # sk_test_ (8) + 32 hex chars
    end

    test "should generate live API key" do
      result = service(:live).call

      assert result[:success]
      assert_instance_of ApiKey, result[:api_key]
      assert result[:plaintext_key].start_with?("sk_live_")
      assert_equal 40, result[:plaintext_key].length  # sk_live_ (8) + 32 hex chars
    end

    test "should hash API key with SHA256" do
      result = service(:test).call
      api_key = result[:api_key]
      plaintext = result[:plaintext_key]

      expected_digest = Digest::SHA256.hexdigest(plaintext)

      assert_equal expected_digest, api_key.key_digest
    end

    test "should store only key prefix" do
      result = service(:test).call
      api_key = result[:api_key]

      assert_equal 12, api_key.key_prefix.length
      assert api_key.key_prefix.start_with?("sk_test_")
    end

    test "should set correct environment" do
      test_result = service(:test).call
      live_result = service(:live).call

      assert test_result[:api_key].test?
      assert live_result[:api_key].live?
    end

    test "should save API key to database" do
      assert_difference -> { ApiKey.count }, 1 do
        service(:test).call
      end
    end

    test "should associate API key with account" do
      result = service(:test).call

      assert_equal account, result[:api_key].account
    end

    test "should accept optional description" do
      result = service(:test).call(description: "Production Server")

      assert_equal "Production Server", result[:api_key].description
    end

    test "should generate unique keys" do
      result1 = service(:test).call
      result2 = service(:test).call

      assert_not_equal result1[:plaintext_key], result2[:plaintext_key]
      assert_not_equal result1[:api_key].key_digest, result2[:api_key].key_digest
    end

    test "should not store plaintext key" do
      result = service(:test).call
      api_key = result[:api_key].reload

      assert_not_equal result[:plaintext_key], api_key.key_digest
      assert_not api_key.key_digest.include?(result[:plaintext_key])
    end

    test "should return error on validation failure" do
      # Temporarily make key_digest fail uniqueness by creating duplicate in same transaction
      existing_key = ApiKey.create!(
        account: account,
        key_digest: "existing_digest",
        key_prefix: "sk_test_exist",
        environment: :test
      )

      # Mock the hash to return existing digest
      service = ApiKeys::GenerationService.new(account, :test)
      service.define_singleton_method(:hash_key) { |_| "existing_digest" }

      result = service.call

      assert_not result[:success]
      assert result[:errors].present?
      assert_includes result[:errors].join, "already been taken"
    end

    private

    def service(environment)
      @service ||= {}
      @service[environment] ||= ApiKeys::GenerationService.new(account, environment)
    end

    def account
      @account ||= accounts(:one)
    end
end
