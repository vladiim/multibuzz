class CreateConversionPropertyKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :conversion_property_keys do |t|
      t.references :account, null: false, foreign_key: true
      t.string :property_key, null: false
      t.integer :occurrences, default: 0, null: false
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :conversion_property_keys, [:account_id, :property_key], unique: true
    add_index :conversion_property_keys, [:account_id, :occurrences]
  end
end
