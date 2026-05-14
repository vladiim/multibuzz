# frozen_string_literal: true

# Identities today store an arbitrary `traits` JSONB. Conversion feedback
# needs normalised hashed PII columns the dispatcher can read directly:
#
# - email_sha256:           SHA-256 of trimmed lowercased email
# - phone_e164_sha256:      SHA-256 of E.164-normalised phone (with + prefix)
# - first_name_sha256:      SHA-256 of trimmed lowercased first name
# - last_name_sha256:       SHA-256 of trimmed lowercased last name
#
# All 64-char hex strings (SHA-256), all NULLable. Identities::IdentificationService
# normalises and hashes server-side from canonical raw fields supplied via
# identify calls. Existing arbitrary `traits` JSONB stays untouched for
# backwards compatibility (customers may already write to traits.email).
#
# Index on email_sha256 (account-scoped) supports the match-rate diagnostic
# in the admin UI.
class AddHashedPiiToIdentities < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :identities, :email_sha256, :string, limit: 64 unless column_exists?(:identities, :email_sha256)
    add_column :identities, :phone_e164_sha256, :string, limit: 64 unless column_exists?(:identities, :phone_e164_sha256)
    add_column :identities, :first_name_sha256, :string, limit: 64 unless column_exists?(:identities, :first_name_sha256)
    add_column :identities, :last_name_sha256, :string, limit: 64 unless column_exists?(:identities, :last_name_sha256)

    add_index :identities, [ :account_id, :email_sha256 ],
      where: "email_sha256 IS NOT NULL",
      algorithm: :concurrently,
      name: "index_identities_on_account_email_sha256" unless index_exists?(:identities, [ :account_id, :email_sha256 ], name: "index_identities_on_account_email_sha256")
  end

  def down
    remove_index :identities, name: "index_identities_on_account_email_sha256", if_exists: true
    remove_column :identities, :last_name_sha256, if_exists: true
    remove_column :identities, :first_name_sha256, if_exists: true
    remove_column :identities, :phone_e164_sha256, if_exists: true
    remove_column :identities, :email_sha256, if_exists: true
  end
end
