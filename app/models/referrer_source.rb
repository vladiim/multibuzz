# frozen_string_literal: true

class ReferrerSource < ApplicationRecord
  include ReferrerSource::Validations
  include ReferrerSource::Scopes
end
