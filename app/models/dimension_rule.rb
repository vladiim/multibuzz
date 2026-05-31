# frozen_string_literal: true

# One ordered match rule for a by-campaign CustomDimension. Matches a campaign
# field with an operator and assigns output_value; first match (by position)
# wins. Operators reuse the shared Dashboard::Scopes::Operators engine.
#
# See lib/specs/custom_dimensions_spec.md.
class DimensionRule < ApplicationRecord
  # --- Match fields (the campaign attribute a rule reads) ---
  CAMPAIGN_NAME = "campaign_name"
  CAMPAIGN_ID = "campaign_id"
  CAMPAIGN_TYPE = "campaign_type"
  NETWORK_TYPE = "network_type"
  DEVICE = "device"
  CHANNEL = "channel"

  # Each match field => the ad_spend_records attribute that backs it. Single
  # source for both the validation list and CustomDimensions::Resolver.
  ROW_ATTRIBUTES = {
    CAMPAIGN_NAME => :campaign_name,
    CAMPAIGN_ID => :platform_campaign_id,
    CAMPAIGN_TYPE => :campaign_type,
    NETWORK_TYPE => :network_type,
    DEVICE => :device,
    CHANNEL => :channel
  }.freeze

  MATCH_FIELDS = ROW_ATTRIBUTES.keys.freeze
  OPERATORS = Dashboard::Scopes::Operators::MATCHABLE
  MAX_VALUE_LENGTH = 500

  include EnqueuesDimensionBackfill

  has_prefix_id :drul

  belongs_to :account
  belongs_to :custom_dimension

  validates :match_field, presence: true, inclusion: { in: MATCH_FIELDS }
  validates :operator, presence: true, inclusion: { in: OPERATORS }
  validates :value, presence: true, length: { maximum: MAX_VALUE_LENGTH }
  validates :output_value, presence: true
  validate :value_compiles_as_regex, if: :regex?
  validate :dimension_supports_rules

  scope :ordered, -> { order(:position) }

  def regex? = operator == Dashboard::Scopes::Operators::REGEX

  private

  def value_compiles_as_regex
    Regexp.new(value.to_s)
  rescue RegexpError
    errors.add(:value, "is not a valid regular expression")
  end

  def dimension_supports_rules
    return if custom_dimension.nil?

    errors.add(:base, "rules apply to by-campaign dimensions only") unless custom_dimension.by_campaign?
  end
end
