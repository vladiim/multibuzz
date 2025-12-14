class AddOnboardingToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :onboarding_progress, :integer, default: 1, null: false
    add_column :accounts, :onboarding_persona, :integer
    add_column :accounts, :selected_sdk, :string
    add_column :accounts, :onboarding_started_at, :datetime
    add_column :accounts, :onboarding_completed_at, :datetime
    add_column :accounts, :activated_at, :datetime
  end
end
