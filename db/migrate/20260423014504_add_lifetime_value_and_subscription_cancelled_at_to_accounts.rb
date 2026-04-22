# frozen_string_literal: true

class AddLifetimeValueAndSubscriptionCancelledAtToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :lifetime_value_cents, :bigint, default: 0, null: false
    add_column :accounts, :subscription_cancelled_at, :datetime
  end
end
