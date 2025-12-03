class ReferrerSource < ApplicationRecord
  include ReferrerSource::Validations
  include ReferrerSource::Scopes
end
