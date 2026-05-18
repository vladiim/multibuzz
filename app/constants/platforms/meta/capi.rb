# frozen_string_literal: true

# Meta Conversions API wire-format constants.
#
# All payload keys, user_data match-key names, and action_source values
# live here so AdDestinations::Meta::* services never embed raw strings
# from Meta's spec. A typo or schema change touches one file.
#
# Reference:
# https://developers.facebook.com/docs/marketing-api/conversions-api/parameters/customer-information-parameters
module Platforms
  module Meta
    module Capi
      GRAPH_HOST = "https://graph.facebook.com"
      API_VERSION = "v22.0"

      module Payload
        DATA = :data
        EVENT_NAME = :event_name
        EVENT_TIME = :event_time
        EVENT_ID = :event_id
        ACTION_SOURCE = :action_source
        EVENT_SOURCE_URL = :event_source_url
        USER_DATA = :user_data
        CUSTOM_DATA = :custom_data
      end

      module UserData
        EXTERNAL_ID = :external_id
        EMAIL = :em
        PHONE = :ph
        FIRST_NAME = :fn
        LAST_NAME = :ln
        COUNTRY = :country
        POSTAL_CODE = :zp
        FBC = :fbc
        FBP = :fbp
      end

      module CustomData
        VALUE = :value
        CURRENCY = :currency
      end

      # https://developers.facebook.com/docs/marketing-api/conversions-api/parameters/server-event/#action-source
      module ActionSources
        WEBSITE = "website"
        APP = "app"
        PHONE_CALL = "phone_call"
        CHAT = "chat"
        EMAIL = "email"
        PHYSICAL_STORE = "physical_store"
        SYSTEM_GENERATED = "system_generated"
        OTHER = "other"
      end

      # Key inside ConversionDestination#event_type_mapping["{conversion_type}"]
      # that holds the platform-specific event name.
      module EventTypeMapping
        META_EVENT_KEY = "meta_event"
      end
    end
  end
end
