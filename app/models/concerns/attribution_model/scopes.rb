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

  def unattributed_conversions
    account.conversions
      .where.not(id: attribution_credits.select(:conversion_id))
  end

  def unattributed_conversions_count
    unattributed_conversions.count
  end

  def has_unattributed_conversions?
    unattributed_conversions.exists?
  end

  def pending_conversions_count
    stale_conversions_count + unattributed_conversions_count
  end

  def needs_backfill?
    has_unattributed_conversions?
  end

  def needs_rerun?
    has_stale_credits? || has_unattributed_conversions?
  end
end
