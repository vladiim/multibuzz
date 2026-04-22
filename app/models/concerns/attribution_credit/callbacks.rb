# frozen_string_literal: true

module AttributionCredit::Callbacks
  extend ActiveSupport::Concern

  SKIP_INVALIDATION_KEY = :skip_dashboard_cache_invalidation

  included do
    after_commit :invalidate_dashboard_cache, on: [ :create, :update, :destroy ], unless: :skip_dashboard_cache_invalidation?
  end

  class_methods do
    def without_dashboard_cache_invalidation
      Thread.current[SKIP_INVALIDATION_KEY] = true
      yield
    ensure
      Thread.current[SKIP_INVALIDATION_KEY] = nil
    end
  end

  private

  def invalidate_dashboard_cache
    Dashboard::CacheInvalidator.new(account).call
  end

  def skip_dashboard_cache_invalidation?
    Thread.current[SKIP_INVALIDATION_KEY] == true
  end
end
