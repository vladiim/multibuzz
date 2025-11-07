class CreateApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :api_keys do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :key_digest, null: false
      t.string :key_prefix, null: false
      t.integer :environment, null: false, default: 0
      t.text :description
      t.datetime :last_used_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :api_keys, :key_digest, unique: true
    add_index :api_keys, :key_prefix
    add_index :api_keys, :environment
    add_index :api_keys, :revoked_at
    add_index :api_keys, [:account_id, :environment]
  end
end
