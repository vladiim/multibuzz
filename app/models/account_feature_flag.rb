# frozen_string_literal: true

class AccountFeatureFlag < ApplicationRecord
  belongs_to :account

  validates :flag_name, presence: true, uniqueness: { scope: :account_id }
end
