# frozen_string_literal: true

module AdSpendRecord::Scopes
  extend ActiveSupport::Concern

  included do
    scope :production, -> { where(is_test: false) }
    scope :test_data, -> { where(is_test: true) }
    scope :for_date_range, ->(range) { where(spend_date: range) }
    scope :for_channel, ->(channel) { where(channel: channel) }
    scope :for_hour, ->(hour) { where(spend_hour: hour) }
    scope :for_device, ->(device) { where(device: device) }
  end
end
