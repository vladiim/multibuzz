# frozen_string_literal: true

module AttributionCredit::Callbacks
  extend ActiveSupport::Concern

  included do
    after_commit :invalidate_dashboard_cache, on: [ :create, :update, :destroy ]
  end

  private

  def invalidate_dashboard_cache
    Dashboard::CacheInvalidator.new(account).call
  end
end
