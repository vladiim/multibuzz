# frozen_string_literal: true

class DataIntegrityCheck < ApplicationRecord
  include DataIntegrityCheck::Validations
  include DataIntegrityCheck::Relationships
  include DataIntegrityCheck::Scopes
end
