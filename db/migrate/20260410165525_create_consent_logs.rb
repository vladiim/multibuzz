# frozen_string_literal: true

# Proof-of-consent storage for the marketing analytics cookie banner.
# Replaces what a CMP vendor like Cookiebot/Termly would store on our
# behalf — required by GDPR Art. 7(1) which says the data controller
# must be able to demonstrate that consent was given.
#
# Anonymous: visitor_id is the _mbuzz_vid cookie value if present, but
# rows are not scoped to an account because the consent decision is
# captured before signup. account_id is set on the rare paths where
# the visitor is already logged in.
class CreateConsentLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :consent_logs do |t|
      t.references :account, null: true, foreign_key: true
      t.string :visitor_id
      t.jsonb :consent_payload, null: false, default: {}
      t.string :ip_hash, null: false
      t.string :country, limit: 2
      t.string :region, limit: 8
      t.string :user_agent
      t.string :banner_version, null: false

      t.timestamps
    end

    add_index :consent_logs, :visitor_id
    add_index :consent_logs, :created_at
  end
end
