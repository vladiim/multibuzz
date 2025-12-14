# frozen_string_literal: true

module AttributionModel::Callbacks
  extend ActiveSupport::Concern

  included do
    before_save :ensure_single_default_per_account
    before_save :increment_version_on_code_change
  end

  private

  def ensure_single_default_per_account
    return unless is_default? && is_default_changed?

    AttributionModel
      .where(account: account, is_default: true)
      .where.not(id: id)
      .update_all(is_default: false)
  end

  def increment_version_on_code_change
    return unless dsl_code_changed?

    self.version = (version || 0) + 1
    self.version_updated_at = Time.current
  end
end
