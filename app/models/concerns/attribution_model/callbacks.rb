# frozen_string_literal: true

module AttributionModel::Callbacks
  extend ActiveSupport::Concern

  included do
    before_save :ensure_single_default_per_account
  end

  private

  def ensure_single_default_per_account
    return unless is_default? && is_default_changed?

    AttributionModel
      .where(account: account, is_default: true)
      .where.not(id: id)
      .update_all(is_default: false)
  end
end
