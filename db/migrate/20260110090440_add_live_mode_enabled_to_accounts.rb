class AddLiveModeEnabledToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :live_mode_enabled, :boolean, default: false, null: false
  end
end
