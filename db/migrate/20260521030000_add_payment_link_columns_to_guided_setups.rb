# frozen_string_literal: true

class AddPaymentLinkColumnsToGuidedSetups < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :guided_setups, :payment_token, :string
    add_column :guided_setups, :payment_token_expires_at, :datetime
    add_column :guided_setups, :kickoff_booked_at, :datetime
    add_index :guided_setups, :payment_token,
              unique: true,
              where: "payment_token IS NOT NULL",
              algorithm: :concurrently
  end
end
