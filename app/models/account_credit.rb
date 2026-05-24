# frozen_string_literal: true

class AccountCredit < ApplicationRecord
  include AccountCredit::Enums
  include AccountCredit::Relationships
  include AccountCredit::Validations

  has_prefix_id :cred
end
