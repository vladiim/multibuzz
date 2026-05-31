# frozen_string_literal: true

# Account-scoped custom dimension: a user-defined attribute (location, brand,
# region, ...) attached to ad spend. Mapped either "by account" (one fixed value
# per connection, via connection.metadata) or "by campaign" (ordered
# dimension_rules). `channel` ships as the built-in dimension.
#
# See lib/specs/custom_dimensions_spec.md.
class CustomDimension < ApplicationRecord
  CHANNEL = "channel"
  BUILT_IN_KEYS = [ CHANNEL ].freeze

  ACCOUNT_MODE = "account"
  CAMPAIGN_MODE = "campaign"
  MAPPING_MODES = [ ACCOUNT_MODE, CAMPAIGN_MODE ].freeze

  include EnqueuesDimensionBackfill

  has_prefix_id :cdim

  belongs_to :account
  has_many :dimension_rules, -> { order(:position) }, dependent: :destroy

  enum :platform, AdPlatformConnection.platforms # nil = all platforms

  before_validation :normalize_key

  validates :key, presence: true, uniqueness: { scope: :account_id }
  validates :name, presence: true
  validates :default_value, presence: true
  validates :mapping_mode, inclusion: { in: MAPPING_MODES }
  validate :key_not_reserved, unless: :built_in?

  scope :active, -> { where(is_active: true) }
  scope :by_account, -> { where(mapping_mode: ACCOUNT_MODE) }
  scope :by_campaign, -> { where(mapping_mode: CAMPAIGN_MODE) }
  scope :user_defined, -> { where(built_in: nil) }
  scope :for_platform, ->(platform) { where(platform: [ nil, platform ]) }

  def by_account? = mapping_mode == ACCOUNT_MODE
  def by_campaign? = mapping_mode == CAMPAIGN_MODE
  def built_in? = built_in.present?
  def channel? = built_in == CHANNEL

  private

  def normalize_key
    self.key = AdPlatforms::MetadataNormalizer.normalize_key(key) if key.present?
  end

  def key_not_reserved
    errors.add(:key, "is reserved") if BUILT_IN_KEYS.include?(key)
  end
end
