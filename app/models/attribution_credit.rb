class AttributionCredit < ApplicationRecord
  belongs_to :account
  belongs_to :conversion
  belongs_to :attribution_model
  belongs_to :session
end
