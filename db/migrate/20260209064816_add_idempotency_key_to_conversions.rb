# frozen_string_literal: true

class AddIdempotencyKeyToConversions < ActiveRecord::Migration[8.0]
  def change
    add_column :conversions, :idempotency_key, :string
    add_index :conversions, [ :account_id, :idempotency_key ],
      unique: true,
      where: "idempotency_key IS NOT NULL",
      name: "index_conversions_on_account_idempotency_key"
  end
end
