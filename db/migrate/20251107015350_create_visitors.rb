class CreateVisitors < ActiveRecord::Migration[8.0]
  def change
    create_table :visitors do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :visitor_id, null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.jsonb :traits, default: {}

      t.timestamps
    end

    add_index :visitors, [:account_id, :visitor_id], unique: true
    add_index :visitors, :visitor_id
    add_index :visitors, :last_seen_at
    add_index :visitors, :traits, using: :gin
  end
end
