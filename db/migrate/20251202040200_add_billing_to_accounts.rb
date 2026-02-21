# frozen_string_literal: true

class AddBillingToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_reference :accounts, :plan, null: true, foreign_key: true

    add_column :accounts, :billing_status, :integer, null: false, default: 0
    add_column :accounts, :stripe_customer_id, :string
    add_column :accounts, :stripe_subscription_id, :string
    add_column :accounts, :billing_email, :string
    add_column :accounts, :free_until, :datetime
    add_column :accounts, :trial_ends_at, :datetime
    add_column :accounts, :subscription_started_at, :datetime
    add_column :accounts, :current_period_start, :datetime
    add_column :accounts, :current_period_end, :datetime
    add_column :accounts, :payment_failed_at, :datetime
    add_column :accounts, :grace_period_ends_at, :datetime

    add_index :accounts, :billing_status
    add_index :accounts, :stripe_customer_id, unique: true
    add_index :accounts, :stripe_subscription_id, unique: true
    add_index :accounts, :free_until
    add_index :accounts, :trial_ends_at
    add_index :accounts, :payment_failed_at
  end
end
