# frozen_string_literal: true

module RerunJob::Scopes
  extend ActiveSupport::Concern

  included do
    scope :recent, -> { order(created_at: :desc) }
    scope :for_model, ->(model) { where(attribution_model: model) }
  end

  def progress_percentage
    return 0 if total_conversions.zero?

    (processed_conversions.to_f / total_conversions * ::Billing::USAGE_LIMIT_THRESHOLD).round
  end

  def increment_processed!(count = 1)
    increment!(:processed_conversions, count)
  end

  def mark_processing!
    update!(status: :processing, started_at: Time.current)
  end

  def mark_completed!
    update!(status: :completed, completed_at: Time.current)
  end

  def mark_failed!(message)
    update!(status: :failed, error_message: message, completed_at: Time.current)
  end
end
