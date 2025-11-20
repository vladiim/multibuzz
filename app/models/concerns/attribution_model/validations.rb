# frozen_string_literal: true

module AttributionModel::Validations
  extend ActiveSupport::Concern

  included do
    validates :name, presence: true
    validates :name,
      uniqueness: { scope: :account_id }
  end
end
