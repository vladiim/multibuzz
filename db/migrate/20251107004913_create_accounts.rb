class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :settings
      t.datetime :suspended_at
      t.datetime :cancelled_at

      t.timestamps
    end

    add_index :accounts, :slug, unique: true
    add_index :accounts, :status
  end
end
