class AddInvitationFieldsToAccountMemberships < ActiveRecord::Migration[8.0]
  def change
    add_column :account_memberships, :invitation_token_digest, :string
    add_column :account_memberships, :invited_by_id, :bigint
    add_column :account_memberships, :last_accessed_at, :datetime

    add_index :account_memberships, :invited_by_id
    add_index :account_memberships, :invitation_token_digest, unique: true
  end
end
