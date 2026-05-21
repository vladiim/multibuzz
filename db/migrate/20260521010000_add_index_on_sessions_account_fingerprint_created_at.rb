# frozen_string_literal: true

# Sessions::CreationService#recent_fingerprint_session looks up
#   account.sessions.where(device_fingerprint: ?).where("created_at > ?", 30.seconds.ago)
# inside an advisory lock held per session create. Without this composite
# index Postgres falls back to index_sessions_on_account_id and filters
# in memory, scanning ~1.2M tuples per call on the largest account.
# That kept mbuzz-db pegged above 85% CPU under load.
#
# Hypertables (dev/test) do not support algorithm: :concurrently. Prod is
# not a hypertable, so the prod index is built CONCURRENTLY out of band
# before this migration runs; the index_exists? guard makes the migration
# a no-op there.
class AddIndexOnSessionsAccountFingerprintCreatedAt < ActiveRecord::Migration[8.0]
  def up
    return if index_exists?(:sessions, [ :account_id, :device_fingerprint, :created_at ],
                            name: "index_sessions_on_account_fingerprint_created_at")

    safety_assured do
      add_index :sessions, [ :account_id, :device_fingerprint, :created_at ],
        where: "device_fingerprint IS NOT NULL",
        name: "index_sessions_on_account_fingerprint_created_at"
    end
  end

  def down
    remove_index :sessions,
      name: "index_sessions_on_account_fingerprint_created_at",
      if_exists: true
  end
end
