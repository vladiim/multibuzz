# frozen_string_literal: true

module ReattributionBatch::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
  end
end
