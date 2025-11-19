# frozen_string_literal: true

module AttributionModel::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    has_many :attribution_credits, dependent: :destroy
  end
end
