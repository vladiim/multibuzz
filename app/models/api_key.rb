class ApiKey < ApplicationRecord
  include ApiKey::Validations
  include ApiKey::Scopes
  include ApiKey::KeyManagement

  belongs_to :account

  enum :environment, { test: 0, live: 1 }
end
