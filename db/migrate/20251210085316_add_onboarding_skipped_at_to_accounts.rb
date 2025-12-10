class AddOnboardingSkippedAtToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :onboarding_skipped_at, :datetime
  end
end
