# frozen_string_literal: true

require "test_helper"

module AdDestinations
  class RegistryTest < ActiveSupport::TestCase
    test "dispatcher_for returns a callable that runs the platform-specific dispatcher" do
      stub_request(:post, %r{graph.facebook.com}).to_return(status: 200, body: "{}")
      destination = build_destination(platform: "meta_capi")
      callable = Registry.dispatcher_for(destination)

      result = callable.call(conversion)

      assert_kind_of ConversionDispatch, result
    end

    test "raises for unknown platform" do
      destination = build_destination(platform: "tiktok_capi")

      assert_raises(ArgumentError) { Registry.dispatcher_for(destination) }
    end

    private

    def conversion
      @conversion ||= accounts(:one).conversions.create!(
        visitor: visitors(:one),
        identity: accounts(:one).identities.create!(
          external_id: "u_registry", first_identified_at: Time.current, last_identified_at: Time.current,
          email_sha256: Identities::Normaliser.sha256("user@example.com")
        ),
        conversion_type: "Lead", converted_at: Time.current,
        idempotency_key: "registry_idem_#{SecureRandom.hex(4)}"
      )
    end

    def build_destination(platform:)
      ConversionDestination.create!(
        account: accounts(:one), attribution_model: attribution_models(:last_touch),
        platform: platform, name: "Test", enabled: true,
        meta_pixel_id: "P_REG", meta_access_token: "TOK_REG"
      )
    rescue ActiveRecord::RecordInvalid
      ConversionDestination.new(
        account: accounts(:one), attribution_model: attribution_models(:last_touch),
        platform: platform, name: "Test"
      )
    end
  end
end
