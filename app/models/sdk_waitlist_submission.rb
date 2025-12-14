# frozen_string_literal: true

class SdkWaitlistSubmission < FormSubmission
  store_accessor :data, :sdk_key, :sdk_name, :account_id

  validates :sdk_key, presence: true
end
