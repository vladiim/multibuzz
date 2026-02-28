# frozen_string_literal: true

module AdPlatformConnection::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    has_many :ad_spend_records, dependent: :destroy
    has_many :ad_spend_sync_runs, dependent: :destroy
  end
end
