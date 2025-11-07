class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :visitor, null: false, foreign_key: true
      t.references :session, null: false, foreign_key: true
      t.string :event_type, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :properties, null: false, default: {}

      t.timestamps
    end

    add_index :events, [ :account_id, :event_type ]
    add_index :events, [ :account_id, :occurred_at ]
    add_index :events, :properties, using: :gin
    add_index :events, "(properties -> 'utm_source')", using: :gin, name: "index_events_on_utm_source"
    add_index :events, "(properties -> 'utm_medium')", using: :gin, name: "index_events_on_utm_medium"
    add_index :events, "(properties -> 'utm_campaign')", using: :gin, name: "index_events_on_utm_campaign"
  end
end
