# frozen_string_literal: true

class CreateAccountCredits < ActiveRecord::Migration[8.0]
  def change
    create_table :account_credits do |t|
      t.references :account, null: false, foreign_key: true
      t.references :applied_plan, null: false, foreign_key: { to_table: :plans }
      t.integer :amount_cents, null: false
      t.string :source, null: false
      t.integer :status, null: false, default: 0
      t.datetime :granted_at, null: false
      t.string :stripe_balance_transaction_id
      t.text :notes
      t.timestamps

      t.index [ :account_id, :status ]
    end
  end
end
