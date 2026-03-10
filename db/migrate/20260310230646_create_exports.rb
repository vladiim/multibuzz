# frozen_string_literal: true

class CreateExports < ActiveRecord::Migration[8.0]
  def change
    create_table :exports do |t|
      t.references :account, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.string :export_type, null: false
      t.string :filename
      t.string :file_path
      t.jsonb :filter_params, default: {}
      t.datetime :completed_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :exports, [ :account_id, :status ]
  end
end
