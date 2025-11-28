class Identity < ApplicationRecord
  include Identity::Validations
  include Identity::Relationships
  include Identity::Scopes

  has_prefix_id :idt
end
