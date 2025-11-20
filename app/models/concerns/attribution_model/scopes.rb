# frozen_string_literal: true

module AttributionModel::Scopes
  extend ActiveSupport::Concern

  included do
    scope :active, -> { where(is_active: true) }
    scope :default_for_account,
      ->(account) { where(account: account, is_default: true).first }
  end
end
