# frozen_string_literal: true

module Visitors
  class DeduplicationService < ApplicationService
    BURST_WINDOW = 30 # seconds
    DEFAULT_SINCE = 90 # days

    def initialize(account, dry_run: false, window: BURST_WINDOW, since_days: DEFAULT_SINCE)
      @account = account
      @dry_run = dry_run
      @window = window
      @since = since_days.days.ago
      @stats = {
        fingerprints_checked: 0,
        groups_merged: 0,
        visitors_merged: 0,
        sessions_reassigned: 0,
        events_reassigned: 0,
        conversions_reassigned: 0
      }
    end

    private

    attr_reader :account, :dry_run, :window, :since, :stats

    def run
      each_duplicate_group do |canonical, duplicates|
        merge_group(canonical, duplicates)
      end

      success_result(stats: stats)
    end

    def each_duplicate_group
      duplicates = fingerprints_with_multiple_visitors
      total = duplicates.size
      Rails.logger.info "Found #{total} fingerprints with multiple visitors" if total > 0

      duplicates.each do |fingerprint, visitor_ids|
        stats[:fingerprints_checked] += 1
        Rails.logger.info "Processing fingerprint #{stats[:fingerprints_checked]}/#{total}" if (stats[:fingerprints_checked] % 50).zero?

        burst_groups_for(fingerprint, visitor_ids).each do |group|
          canonical = group.first
          duplicates = group[1..]
          yield canonical, duplicates if duplicates.any?
        end
      end

      Rails.logger.info "Deduplication scan complete" if total > 0
    end

    def fingerprints_with_multiple_visitors
      account.sessions
        .where.not(device_fingerprint: nil)
        .where("started_at > ?", since)
        .group(:device_fingerprint)
        .having("COUNT(DISTINCT visitor_id) > 1")
        .pluck(:device_fingerprint, Arel.sql("array_agg(DISTINCT visitor_id)"))
        .to_h
    end

    def burst_groups_for(_fingerprint, visitor_ids)
      visitors = account.visitors
        .where(id: visitor_ids)
        .order(:created_at)
        .to_a

      cluster_by_burst(visitors)
    end

    def cluster_by_burst(visitors)
      groups = []
      current_group = [visitors.first]

      visitors[1..].each do |visitor|
        if (visitor.created_at - current_group.first.created_at).abs <= window
          current_group << visitor
        else
          groups << current_group if current_group.size > 1
          current_group = [visitor]
        end
      end

      groups << current_group if current_group.size > 1
      groups
    end

    def merge_group(canonical, duplicates)
      stats[:groups_merged] += 1
      stats[:visitors_merged] += duplicates.size

      return if dry_run

      duplicate_ids = duplicates.map(&:id)

      ActiveRecord::Base.transaction do
        reassign_sessions(canonical, duplicate_ids)
        reassign_events(canonical, duplicate_ids)
        reassign_conversions(canonical, duplicate_ids)
        inherit_identity(canonical, duplicates)
        update_timestamps(canonical, duplicates)
        delete_duplicates(duplicate_ids)
      end
    end

    def reassign_sessions(canonical, duplicate_ids)
      count = account.sessions.where(visitor_id: duplicate_ids).update_all(visitor_id: canonical.id)
      stats[:sessions_reassigned] += count
    end

    def reassign_events(canonical, duplicate_ids)
      count = account.events.where(visitor_id: duplicate_ids).update_all(visitor_id: canonical.id)
      stats[:events_reassigned] += count
    end

    def reassign_conversions(canonical, duplicate_ids)
      count = account.conversions.where(visitor_id: duplicate_ids).update_all(visitor_id: canonical.id)
      stats[:conversions_reassigned] += count
    end

    def inherit_identity(canonical, duplicates)
      return if canonical.identity_id.present?

      donor = duplicates.find { |v| v.identity_id.present? }
      canonical.update_column(:identity_id, donor.identity_id) if donor
    end

    def update_timestamps(canonical, duplicates)
      all_visitors = [canonical] + duplicates
      earliest_first_seen = all_visitors.map(&:first_seen_at).min
      latest_last_seen = all_visitors.map(&:last_seen_at).max

      canonical.update_columns(
        first_seen_at: earliest_first_seen,
        last_seen_at: latest_last_seen
      )
    end

    def delete_duplicates(duplicate_ids)
      Visitor.where(id: duplicate_ids).delete_all
    end
  end
end
