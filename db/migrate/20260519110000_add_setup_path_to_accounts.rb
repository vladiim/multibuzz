# frozen_string_literal: true

class AddSetupPathToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :setup_path, :integer
  end
end
