class AddSessionResolutionColumns < ActiveRecord::Migration[8.0]
  def change
    add_column :sessions, :last_activity_at, :datetime
    add_column :sessions, :device_fingerprint, :string

    add_index :sessions, [:visitor_id, :device_fingerprint, :last_activity_at],
      name: "index_sessions_for_resolution"

    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE sessions SET last_activity_at = started_at WHERE last_activity_at IS NULL
        SQL
      end
    end
  end
end
