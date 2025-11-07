module Account::Relationships
  extend ActiveSupport::Concern

  included do
    has_many :api_keys, dependent: :destroy
    has_many :visitors, dependent: :destroy
    has_many :sessions, dependent: :destroy
    has_many :events, dependent: :destroy
  end
end
