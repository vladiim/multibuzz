class AddSuspectToSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sessions, :suspect, :boolean, default: false, null: false
  end
end
