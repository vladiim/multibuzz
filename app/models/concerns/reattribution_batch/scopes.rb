# frozen_string_literal: true

module ReattributionBatch::Scopes
  extend ActiveSupport::Concern

  included do
    scope :recent, -> { order(created_at: :desc) }
    scope :unfinished, -> { where(status: [ :pending, :processing ]) }
  end

  def increment_processed!(count = 1)
    increment!(:processed, count)
  end

  def increment_failed!(count = 1)
    increment!(:failed, count)
  end

  def mark_processing!
    update!(status: :processing, started_at: Time.current)
  end

  def mark_completed!
    update!(status: :completed, completed_at: Time.current)
  end

  def mark_failed!
    update!(status: :failed, completed_at: Time.current)
  end
end
