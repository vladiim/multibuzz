# frozen_string_literal: true

# Load bot patterns on boot so the BotClassifier has data from the first request.
# Patterns are compiled into a Regexp.union and held in memory (class-level singleton).
# The daily SyncJob refreshes them from upstream lists.
#
# Development: sync in background thread (MemoryStore, must be same process).
# Production: enqueue job (SolidCache persists across processes).
Rails.application.config.after_initialize do
  next if Rails.env.test?
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?

  if Rails.env.local?
    Thread.new { BotPatterns::SyncService.new.call } # rubocop:disable ThreadSafety/NewThread
  else
    BotPatterns::SyncJob.perform_later
  end
rescue StandardError => e
  Rails.logger.warn("Bot pattern sync skipped on boot: #{e.message}")
end
