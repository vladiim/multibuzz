class Conversion < ApplicationRecord
  belongs_to :account
  belongs_to :visitor
  belongs_to :session
  belongs_to :event
end
