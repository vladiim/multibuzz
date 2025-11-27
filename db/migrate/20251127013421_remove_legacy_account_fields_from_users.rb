class RemoveLegacyAccountFieldsFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_reference :users, :account, foreign_key: true
    remove_column :users, :role, :integer
  end
end
