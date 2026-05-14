# frozen_string_literal: true

# Builds a Meta Conversions API event payload from a Conversion + the
# resolved match keys + the destination's event_type_mapping. Pure
# function: no HTTP, no I/O, no side effects.
#
# Wire-format keys live in Platforms::Meta::Capi::*.
#
# **No client_ip_address, no client_user_agent, ever.** mbuzz declines
# to send raw IP / UA. See lib/specs/conversion_feedback_spec.md
# "No IP, no UA, ever".
module AdDestinations
  module Meta
    class PayloadBuilder
      DEFAULT_EVENT_TYPE_MAPPING = {}.freeze

      def initialize(conversion:, destination:, match_keys:)
        @conversion = conversion
        @destination = destination
        @match_keys = match_keys
      end

      def call
        { Platforms::Meta::Capi::Payload::DATA => [ event ] }
      end

      private

      attr_reader :conversion, :destination, :match_keys

      def event
        {
          Platforms::Meta::Capi::Payload::EVENT_NAME => event_name,
          Platforms::Meta::Capi::Payload::EVENT_TIME => conversion.converted_at.to_i,
          Platforms::Meta::Capi::Payload::EVENT_ID => conversion.idempotency_key,
          Platforms::Meta::Capi::Payload::ACTION_SOURCE => Platforms::Meta::Capi::ActionSources::WEBSITE,
          Platforms::Meta::Capi::Payload::USER_DATA => user_data,
          Platforms::Meta::Capi::Payload::CUSTOM_DATA => custom_data
        }.compact
      end

      def event_name
        platform_mapping[Platforms::Meta::Capi::EventTypeMapping::META_EVENT_KEY] || conversion.conversion_type
      end

      def platform_mapping
        (destination.event_type_mapping || DEFAULT_EVENT_TYPE_MAPPING)[conversion.conversion_type] || DEFAULT_EVENT_TYPE_MAPPING
      end

      def user_data
        hashed_user_data.merge(cookie_user_data).compact
      end

      def hashed_user_data
        {
          Platforms::Meta::Capi::UserData::EXTERNAL_ID => array_or_nil(match_keys.external_id),
          Platforms::Meta::Capi::UserData::EMAIL       => array_or_nil(match_keys.em),
          Platforms::Meta::Capi::UserData::PHONE       => array_or_nil(match_keys.ph),
          Platforms::Meta::Capi::UserData::FIRST_NAME  => array_or_nil(match_keys.fn),
          Platforms::Meta::Capi::UserData::LAST_NAME   => array_or_nil(match_keys.ln),
          Platforms::Meta::Capi::UserData::COUNTRY     => array_or_nil(hashed_country),
          Platforms::Meta::Capi::UserData::POSTAL_CODE => array_or_nil(hashed_zp)
        }
      end

      def cookie_user_data
        {
          Platforms::Meta::Capi::UserData::FBC => match_keys.fbc,
          Platforms::Meta::Capi::UserData::FBP => match_keys.fbp
        }
      end

      def hashed_country
        Identities::Normaliser.sha256(match_keys.country)
      end

      def hashed_zp
        Identities::Normaliser.sha256(match_keys.zp)
      end

      def custom_data
        return nil if conversion.revenue.blank?

        {
          Platforms::Meta::Capi::CustomData::VALUE => conversion.revenue.to_f,
          Platforms::Meta::Capi::CustomData::CURRENCY => conversion.currency
        }.compact
      end

      def array_or_nil(value)
        value.present? ? [ value ] : nil
      end
    end
  end
end
