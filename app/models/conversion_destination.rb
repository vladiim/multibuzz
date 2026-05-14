# frozen_string_literal: true

# Per-account, per-platform outbound conversion-feedback destination.
# One row holds where to send conversions (Pixel ID, conversion action
# resource name, etc.) plus the attribution-model + revenue-mode rule
# that decides which conversions fire and at what revenue value.
#
# Created by `Conversions::DispatchService` in Phase 6 to discover the
# enabled destinations for an incoming conversion.
class ConversionDestination < ApplicationRecord
  PLATFORMS = %w[meta_capi google_ec].freeze
  REVENUE_MODES = %w[full scaled].freeze

  has_prefix_id :cdest

  encrypts :meta_access_token

  belongs_to :account
  belongs_to :attribution_model
  belongs_to :ad_platform_connection, optional: true
  has_many :conversion_dispatches, dependent: :destroy

  validates :name, presence: true
  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :revenue_mode, presence: true, inclusion: { in: REVENUE_MODES }
  validates :minimum_credit_threshold,
    numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }

  scope :enabled, -> { where(enabled: true) }
  scope :for_platform, ->(platform) { where(platform: platform) }

  def meta?
    platform == "meta_capi"
  end

  def google?
    platform == "google_ec"
  end
end
