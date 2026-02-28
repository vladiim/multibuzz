# frozen_string_literal: true

module AdSpendSyncRun::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :ad_platform_connection
  end
end
