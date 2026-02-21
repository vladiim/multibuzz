# frozen_string_literal: true

module Identity::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    has_many :visitors, dependent: :nullify
    has_many :conversions, dependent: :nullify
  end
end
