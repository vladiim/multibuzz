# frozen_string_literal: true

module RerunJob::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    belongs_to :attribution_model
  end
end
