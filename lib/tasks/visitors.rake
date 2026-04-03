# frozen_string_literal: true

namespace :visitors do
  desc "Merge duplicate visitors created by concurrent sub-requests (same device fingerprint)"
  task deduplicate: :environment do
    account_id = ENV["ACCOUNT_ID"]
    dry_run = ENV["DRY_RUN"] != "false"
    window = (ENV["WINDOW"] || 30).to_i

    unless account_id
      puts "Usage: bin/rails visitors:deduplicate ACCOUNT_ID=123 [DRY_RUN=true] [WINDOW=30]"
      puts ""
      puts "  ACCOUNT_ID  - Required. The account to deduplicate."
      puts "  DRY_RUN     - Default: true. Set DRY_RUN=false to execute changes."
      puts "  WINDOW      - Default: 30. Seconds within which visitors are considered duplicates."
      exit 1
    end

    account = Account.find(account_id)
    puts "=" * 70
    puts "VISITOR DEDUPLICATION — #{account.name} (ID: #{account.id})"
    puts "Window: #{window}s | Mode: #{dry_run ? 'DRY RUN' : '⚠️  LIVE'}"
    puts "=" * 70

    result = Visitors::DeduplicationService.new(account, dry_run: dry_run, window: window).call

    if result[:success]
      stats = result[:stats]
      puts "\n=== RESULTS ==="
      puts "Fingerprints checked:    #{stats[:fingerprints_checked]}"
      puts "Merge groups found:      #{stats[:groups_merged]}"
      puts "Visitors merged:         #{stats[:visitors_merged]}"
      puts "Sessions reassigned:     #{stats[:sessions_reassigned]}"
      puts "Events reassigned:       #{stats[:events_reassigned]}"
      puts "Conversions reassigned:  #{stats[:conversions_reassigned]}"

      if dry_run && stats[:visitors_merged] > 0
        puts "\nThis was a DRY RUN. To execute: bin/rails visitors:deduplicate ACCOUNT_ID=#{account.id} DRY_RUN=false"
      end
    else
      puts "\nERROR: #{result[:errors].join(', ')}"
      exit 1
    end
  end
end
