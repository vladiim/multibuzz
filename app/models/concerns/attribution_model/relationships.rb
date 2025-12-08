# frozen_string_literal: true

module AttributionModel::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    has_many :attribution_credits, dependent: :destroy
    has_many :rerun_jobs, dependent: :destroy
  end
end
