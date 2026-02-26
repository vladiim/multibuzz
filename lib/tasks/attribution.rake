# frozen_string_literal: true

namespace :attribution do
  desc "Backfill session channels using corrected ChannelAttributionService"
  task backfill_channels: :environment do
    account_id = ENV["ACCOUNT_ID"]
    dry_run = ENV["DRY_RUN"] == "true"

    unless account_id
      puts "Usage: bin/rails attribution:backfill_channels ACCOUNT_ID=123 [DRY_RUN=true]"
      exit 1
    end

    account = Account.find(account_id)
    puts "Backfilling channels for account: #{account.name} (ID: #{account.id})"
    puts "DRY RUN MODE - no changes will be made" if dry_run

    stats = { total: 0, updated: 0, unchanged: 0, errors: 0, by_channel: Hash.new(0) }

    account_domains = account.sessions
      .where.not(landing_page_host: nil)
      .distinct.pluck(:landing_page_host)

    account.sessions.includes(:events).find_each do |session|
      stats[:total] += 1

      # Extract page_host from first event for internal referrer detection
      first_event = session.events.order(:occurred_at).first
      page_host = session.landing_page_host || first_event&.properties&.dig("host")

      new_channel = Sessions::ChannelAttributionService.new(
        session.initial_utm || {},
        session.initial_referrer,
        session.click_ids || {},
        page_host: page_host,
        account_domains: account_domains
      ).call

      if session.channel == new_channel
        stats[:unchanged] += 1
      else
        old_channel = session.channel
        stats[:by_channel]["#{old_channel} -> #{new_channel}"] += 1

        unless dry_run
          session.update_column(:channel, new_channel)
        end

        stats[:updated] += 1
      end

      print "\rProcessed: #{stats[:total]} sessions" if (stats[:total] % 100).zero?
    rescue StandardError => e
      stats[:errors] += 1
      puts "\nError processing session #{session.id}: #{e.message}"
    end

    puts "\n\n=== RESULTS ==="
    puts "Total sessions: #{stats[:total]}"
    puts "Updated: #{stats[:updated]}"
    puts "Unchanged: #{stats[:unchanged]}"
    puts "Errors: #{stats[:errors]}"
    puts "\nChannel changes:"
    stats[:by_channel].sort_by { |_, v| -v }.each do |change, count|
      puts "  #{change}: #{count}"
    end
  end

  desc "Reattribute all conversions for an account"
  task reattribute_conversions: :environment do
    account_id = ENV["ACCOUNT_ID"]
    dry_run = ENV["DRY_RUN"] == "true"

    unless account_id
      puts "Usage: bin/rails attribution:reattribute_conversions ACCOUNT_ID=123 [DRY_RUN=true]"
      exit 1
    end

    account = Account.find(account_id)
    puts "Reattributing conversions for account: #{account.name} (ID: #{account.id})"
    puts "DRY RUN MODE - no changes will be made" if dry_run

    stats = { total: 0, success: 0, no_identity: 0, errors: 0 }

    account.conversions.find_each do |conversion|
      stats[:total] += 1

      unless conversion.visitor&.identity
        stats[:no_identity] += 1
        next
      end

      unless dry_run
        result = Conversions::ReattributionService.new(conversion).call

        if result[:success]
          stats[:success] += 1
        else
          stats[:errors] += 1
          puts "\nError reattributing conversion #{conversion.id}: #{result[:errors].join(', ')}"
        end
      else
        stats[:success] += 1
      end

      print "\rProcessed: #{stats[:total]} conversions" if (stats[:total] % 10).zero?
    rescue StandardError => e
      stats[:errors] += 1
      puts "\nError processing conversion #{conversion.id}: #{e.message}"
    end

    puts "\n\n=== RESULTS ==="
    puts "Total conversions: #{stats[:total]}"
    puts "Successfully reattributed: #{stats[:success]}"
    puts "Skipped (no identity): #{stats[:no_identity]}"
    puts "Errors: #{stats[:errors]}"
  end

  desc "Fix sessions where internal referrer was misclassified as referral"
  task fix_internal_referrers: :environment do
    account_id = ENV["ACCOUNT_ID"]
    dry_run = ENV["DRY_RUN"] == "true"

    unless account_id
      puts "Usage: bin/rails attribution:fix_internal_referrers ACCOUNT_ID=123 [DRY_RUN=true]"
      exit 1
    end

    account = Account.find(account_id)
    puts "Fixing internal referrer sessions for: #{account.name} (ID: #{account.id})"
    puts "DRY RUN MODE - no changes will be made" if dry_run

    stats = { total: 0, fixed: 0, unchanged: 0, errors: 0 }

    # Only look at sessions classified as 'referral' with a referrer
    referral_sessions = account.sessions
      .where(channel: "referral")
      .where.not(initial_referrer: [ nil, "" ])
      .includes(:events)

    # Helper lambdas for host extraction and normalization
    extract_host = lambda do |url|
      return nil if url.blank?

      url = "https://#{url}" unless url.include?("://")
      URI.parse(url).host
    rescue URI::InvalidURIError
      nil
    end

    normalize_host = ->(host) { host.to_s.downcase.sub(/^www\./, "").sub(/:\d+$/, "") }

    referral_sessions.find_each do |session|
      stats[:total] += 1

      first_event = session.events.order(:occurred_at).first
      page_host = first_event&.properties&.dig("host")

      next stats[:unchanged] += 1 unless page_host.present?

      referrer_host = extract_host.call(session.initial_referrer)
      next stats[:unchanged] += 1 unless referrer_host.present?

      # Check if referrer host matches page host (internal referrer)
      if normalize_host.call(referrer_host) == normalize_host.call(page_host)
        unless dry_run
          session.update_column(:channel, "direct")
        end
        stats[:fixed] += 1
        puts "  Fixed: Session #{session.id} (#{referrer_host} -> #{page_host})" if ENV["VERBOSE"]
      else
        stats[:unchanged] += 1
      end

      print "\rProcessed: #{stats[:total]} sessions" if (stats[:total] % 100).zero?
    rescue StandardError => e
      stats[:errors] += 1
      puts "\nError processing session #{session.id}: #{e.message}"
    end

    puts "\n\n=== RESULTS ==="
    puts "Total referral sessions checked: #{stats[:total]}"
    puts "Fixed (internal -> direct): #{stats[:fixed]}"
    puts "Unchanged (external referrers): #{stats[:unchanged]}"
    puts "Errors: #{stats[:errors]}"
  end

  desc "Backfill identity_id and recompute journeys for broken conversions"
  task backfill_journeys: :environment do
    account_id = ENV["ACCOUNT_ID"]
    dry_run = ENV["DRY_RUN"] == "true"
    limit = ENV["LIMIT"]&.to_i

    unless account_id
      puts "Usage: bin/rails attribution:backfill_journeys ACCOUNT_ID=123 [DRY_RUN=true] [LIMIT=100]"
      exit 1
    end

    account = Account.find(account_id)
    puts "Backfilling journeys for: #{account.name} (ID: #{account.id})"
    puts "DRY RUN MODE — no changes will be made" if dry_run
    puts "LIMIT: #{limit}" if limit

    stats = { identity_stamped: 0, recomputed: 0, credits_cleared: 0, skipped: 0, errors: 0 }

    # Step 1: Stamp identity_id on conversions where visitor has identity
    stampable = account.conversions
      .where(identity_id: nil)
      .joins(:visitor)
      .where.not(visitors: { identity_id: nil })

    stamp_count = stampable.count
    puts "\n=== Step 1: Stamp identity_id (#{stamp_count} conversions) ==="

    unless dry_run
      stampable.update_all(
        "identity_id = (SELECT identity_id FROM visitors WHERE visitors.id = conversions.visitor_id)"
      )
    end

    stats[:identity_stamped] = stamp_count
    puts "  Stamped: #{stamp_count}"

    # Step 2: Recompute attribution for conversions that need it
    # - Empty journey_session_ids (40% — attribution job failed silently)
    # - Has identity (upgrade single-visitor → cross-device journey)
    # - Skip: no identity + journey already populated (already correct)
    scope = account.conversions
      .where("journey_session_ids = '{}' OR journey_session_ids IS NULL OR identity_id IS NOT NULL")
    scope = scope.limit(limit) if limit

    total = scope.count
    puts "\n=== Step 2: Recompute attribution (#{total} conversions) ==="

    scope.find_each do |conversion|
      old_credits = conversion.attribution_credits.count

      unless dry_run
        conversion.attribution_credits.delete_all if old_credits > 0
        stats[:credits_cleared] += old_credits

        result = Conversions::AttributionCalculationService.new(conversion).call

        if result[:success]
          stats[:recomputed] += 1
        else
          stats[:errors] += 1
          puts "\n  Error: conversion #{conversion.id}: #{result[:errors].join(', ')}"
        end
      else
        stats[:recomputed] += 1
        stats[:credits_cleared] += old_credits
      end

      print "\rProcessed: #{stats[:recomputed] + stats[:errors]}/#{total}" if ((stats[:recomputed] + stats[:errors]) % 10).zero?
    rescue StandardError => e
      stats[:errors] += 1
      puts "\n  Error: conversion #{conversion.id}: #{e.message}"
    end

    puts "\n\n=== RESULTS ==="
    puts "Identity stamped: #{stats[:identity_stamped]}"
    puts "Recomputed: #{stats[:recomputed]}"
    puts "Old credits cleared: #{stats[:credits_cleared]}"
    puts "Errors: #{stats[:errors]}"
  end

  desc "Fix sessions whose channel was overwritten to direct by event processing bug"
  task fix_event_channel_overwrite: :environment do
    account_id = ENV["ACCOUNT_ID"]
    dry_run = ENV["DRY_RUN"] == "true"

    unless account_id
      puts "Usage: bin/rails attribution:fix_event_channel_overwrite ACCOUNT_ID=123 [DRY_RUN=true]"
      exit 1
    end

    account = Account.find(account_id)
    puts "Fixing event channel overwrite for: #{account.name} (ID: #{account.id})"
    puts "DRY RUN MODE - no changes will be made" if dry_run

    account_domains = account.sessions
      .where.not(landing_page_host: nil)
      .distinct.pluck(:landing_page_host)

    stats = { total: 0, fixed: 0, unchanged: 0, errors: 0, by_channel: Hash.new(0) }

    # Target: sessions marked "direct" that have click_ids or initial_referrer
    # These were likely overwritten by the capture_utm_if_new_session bug
    corrupted = account.sessions
      .where(channel: "direct")
      .where("click_ids IS NOT NULL AND click_ids != '{}'::jsonb OR initial_referrer IS NOT NULL")

    total = corrupted.count
    puts "Found #{total} potentially corrupted sessions\n"

    corrupted.find_each do |session|
      stats[:total] += 1

      new_channel = Sessions::ChannelAttributionService.new(
        session.initial_utm || {},
        session.initial_referrer,
        session.click_ids || {},
        page_host: session.landing_page_host,
        account_domains: account_domains
      ).call

      if new_channel == "direct"
        stats[:unchanged] += 1
      else
        stats[:by_channel][new_channel] += 1
        session.update_column(:channel, new_channel) unless dry_run
        stats[:fixed] += 1
      end

      print "\rProcessed: #{stats[:total]}/#{total}" if (stats[:total] % 100).zero?
    rescue StandardError => e
      stats[:errors] += 1
      puts "\nError processing session #{session.id}: #{e.message}"
    end

    puts "\n\n=== RESULTS ==="
    puts "Total checked: #{stats[:total]}"
    puts "Fixed: #{stats[:fixed]}"
    puts "Unchanged (legitimately direct): #{stats[:unchanged]}"
    puts "Errors: #{stats[:errors]}"
    puts "\nRecovered channels:"
    stats[:by_channel].sort_by { |_, v| -v }.each do |channel, count|
      puts "  #{channel}: #{count}"
    end

    if stats[:fixed] > 0 && !dry_run
      puts "\nRun attribution:reattribute_conversions ACCOUNT_ID=#{account_id} to update conversion credits"
    end
  end

  desc "Fix orphan sessions created by event processing with mismatched fingerprints"
  task fix_orphan_sessions: :environment do
    account_id = ENV["ACCOUNT_ID"]
    dry_run = ENV["DRY_RUN"] == "true"

    unless account_id
      puts "Usage: bin/rails attribution:fix_orphan_sessions ACCOUNT_ID=123 [DRY_RUN=true]"
      exit 1
    end

    account = Account.find(account_id)
    puts "Fixing orphan sessions for: #{account.name} (ID: #{account.id})"
    puts "DRY RUN MODE - no changes will be made" if dry_run

    stats = { fixed: 0, skipped: 0, errors: 0 }

    orphans = account.sessions
      .where(landing_page_host: nil)
      .where.not(channel: nil)
      .joins(:events)
      .distinct

    total = orphans.count
    puts "Found #{total} orphan sessions\n"

    orphans.find_each do |orphan|
      prior = account.sessions
        .where(visitor_id: orphan.visitor_id)
        .where.not(id: orphan.id)
        .where("started_at <= ?", orphan.started_at)
        .order(started_at: :desc)
        .first

      unless prior
        stats[:skipped] += 1
        next
      end

      unless dry_run
        ActiveRecord::Base.transaction do
          orphan.events.update_all(session_id: prior.id)
          prior.update!(last_activity_at: [prior.last_activity_at, orphan.last_activity_at].max)
          orphan.conversions.update_all(session_id: prior.id) if orphan.conversions.any?
          orphan.destroy!
        end
      end

      stats[:fixed] += 1
      print "\rProcessed: #{stats[:fixed] + stats[:skipped]}/#{total}" if ((stats[:fixed] + stats[:skipped]) % 100).zero?
    rescue StandardError => e
      stats[:errors] += 1
      puts "\nError processing session #{orphan.id}: #{e.message}"
    end

    puts "\n\n=== RESULTS ==="
    puts "Fixed: #{stats[:fixed]}"
    puts "Skipped (no prior session): #{stats[:skipped]}"
    puts "Errors: #{stats[:errors]}"
  end

  desc "Full backfill: channels + reattribution"
  task full_backfill: :environment do
    account_id = ENV["ACCOUNT_ID"]
    dry_run = ENV["DRY_RUN"] == "true"

    unless account_id
      puts "Usage: bin/rails attribution:full_backfill ACCOUNT_ID=123 [DRY_RUN=true]"
      exit 1
    end

    puts "=== Step 1: Backfill Session Channels ==="
    Rake::Task["attribution:backfill_channels"].invoke

    puts "\n\n=== Step 2: Reattribute Conversions ==="
    Rake::Task["attribution:reattribute_conversions"].invoke
  end
end
