class AddUserAgentToSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sessions, :user_agent, :text
    add_column :sessions, :suspect_reason, :string
  end
end
