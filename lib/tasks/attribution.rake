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

    account.sessions.includes(:events).find_each do |session|
      stats[:total] += 1

      # Extract page_host from first event for internal referrer detection
      first_event = session.events.order(:occurred_at).first
      page_host = first_event&.properties&.dig("host")

      new_channel = Sessions::ChannelAttributionService.new(
        session.initial_utm || {},
        session.initial_referrer,
        session.click_ids || {},
        page_host: page_host
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
      .where.not(initial_referrer: [nil, ""])
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
