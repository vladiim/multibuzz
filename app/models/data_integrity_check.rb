class DataIntegrityCheck < ApplicationRecord
  include DataIntegrityCheck::Validations
  include DataIntegrityCheck::Relationships
  include DataIntegrityCheck::Scopes
end
