# frozen_string_literal: true

module AdSpendRecord::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    belongs_to :ad_platform_connection
  end
end
