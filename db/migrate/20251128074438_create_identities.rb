class CreateIdentities < ActiveRecord::Migration[8.0]
  def change
    create_table :identities do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :external_id, null: false
      t.jsonb :traits, default: {}
      t.datetime :first_identified_at, null: false
      t.datetime :last_identified_at, null: false
      t.boolean :is_test, default: false, null: false

      t.timestamps
    end

    add_index :identities, [:account_id, :external_id], unique: true
    add_index :identities, :external_id
    add_index :identities, :traits, using: :gin
    add_index :identities, :is_test
  end
end
