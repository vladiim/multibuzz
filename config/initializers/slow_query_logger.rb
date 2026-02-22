# frozen_string_literal: true

ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
  duration = payload[:duration] || 0

  if duration > Infrastructure::SLOW_QUERY_THRESHOLD_MS
    Rails.logger.warn("[SLOW QUERY #{duration.round}ms] #{payload[:sql]&.truncate(500)}")
  end
end
