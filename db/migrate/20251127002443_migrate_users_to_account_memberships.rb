class MigrateUsersToAccountMemberships < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      INSERT INTO account_memberships (user_id, account_id, role, status, accepted_at, created_at, updated_at)
      SELECT
        id,
        account_id,
        CASE role WHEN 1 THEN 3 ELSE 1 END,
        1,
        created_at,
        NOW(),
        NOW()
      FROM users
      WHERE account_id IS NOT NULL
    SQL
  end

  def down
    execute "DELETE FROM account_memberships"
  end
end
