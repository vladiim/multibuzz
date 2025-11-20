# frozen_string_literal: true

module AttributionCredit::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    belongs_to :conversion
    belongs_to :attribution_model
    # No belongs_to :session due to TimescaleDB composite PK
  end
end
