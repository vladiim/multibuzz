# frozen_string_literal: true

module AttributionModel::Scopes
  extend ActiveSupport::Concern

  included do
    scope :active, -> { where(is_active: true) }
    scope :default_for_account,
      ->(account) { where(account: account, is_default: true).first }
  end

  def stale_credits
    attribution_credits.where("model_version < ? OR model_version IS NULL", version)
  end

  def stale_credits_count
    stale_credits.count
  end

  def has_stale_credits?
    stale_credits.exists?
  end

  def stale_conversions_count
    stale_credits
      .select(:conversion_id)
      .distinct
      .count
  end
end
