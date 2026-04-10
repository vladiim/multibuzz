# frozen_string_literal: true

# Proof-of-consent log for the marketing analytics cookie banner. Each
# row records a single consent decision (accept all, reject all,
# customise) made by a visitor on mbuzz.co. Required by GDPR Art. 7(1)
# which says the data controller must be able to demonstrate that
# consent was given.
#
# Anonymous: rows are not scoped to an account because the consent
# decision is captured before signup. account_id is set on the rare
# paths where the visitor is already logged in.
class ConsentLog < ApplicationRecord
  belongs_to :account, optional: true

  validates :consent_payload, presence: true
  validates :ip_hash, presence: true
  validates :banner_version, presence: true
end
