class AddChannelAttributionToSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sessions, :initial_referrer, :string
    add_column :sessions, :channel, :string

    add_index :sessions, :channel
  end
end
