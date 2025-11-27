class AddIsTestToTrackingTables < ActiveRecord::Migration[8.0]
  def change
    add_column :visitors, :is_test, :boolean, default: false, null: false
    add_column :sessions, :is_test, :boolean, default: false, null: false
    add_column :events, :is_test, :boolean, default: false, null: false
    add_column :conversions, :is_test, :boolean, default: false, null: false
    add_column :attribution_credits, :is_test, :boolean, default: false, null: false

    add_index :visitors, :is_test
    add_index :sessions, :is_test
    add_index :events, :is_test
    add_index :conversions, :is_test
    add_index :attribution_credits, :is_test
  end
end
