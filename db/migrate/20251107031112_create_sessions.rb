class CreateSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :sessions do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :visitor, null: false, foreign_key: true, index: true
      t.string :session_id, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :page_view_count, null: false, default: 0
      t.jsonb :initial_utm, default: {}

      t.timestamps
    end

    add_index :sessions, [:account_id, :session_id], unique: true
    add_index :sessions, :session_id
    add_index :sessions, :ended_at
    add_index :sessions, :started_at
    add_index :sessions, :initial_utm, using: :gin
  end
end
