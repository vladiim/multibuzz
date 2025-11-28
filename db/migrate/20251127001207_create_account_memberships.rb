class CreateAccountMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :account_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.integer :role, null: false, default: 1
      t.integer :status, null: false, default: 1
      t.datetime :invited_at
      t.datetime :accepted_at
      t.string :invited_by_email
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :account_memberships, [:user_id, :account_id],
      unique: true,
      where: "deleted_at IS NULL",
      name: "index_account_memberships_unique_active"
    add_index :account_memberships, [:account_id, :role]
    add_index :account_memberships, [:account_id, :status]
    add_index :account_memberships, :deleted_at
  end
end
