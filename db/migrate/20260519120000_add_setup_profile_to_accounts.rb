# frozen_string_literal: true

class AddSetupProfileToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :setup_profile, :jsonb, null: false, default: {}
    add_column :accounts, :setup_profile_completed_at, :datetime
  end
end
