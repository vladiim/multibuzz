# frozen_string_literal: true

namespace :data_integrity do
  desc "Remove ghost session IDs from conversion journeys and re-run attribution"
  task cleanup_ghost_journeys: :environment do
    account_id = ENV["ACCOUNT_ID"]

    unless account_id
      puts "Usage: bin/rails data_integrity:cleanup_ghost_journeys ACCOUNT_ID=123"
      exit 1
    end

    account = Account.find(account_id)
    suspect_count = account.sessions.where(suspect: true).count
    total_count = account.sessions.count

    puts "Account: #{account.name} (ID: #{account.id})"
    puts "Suspect sessions: #{suspect_count}/#{total_count} (#{(suspect_count.to_f / total_count * 100).round(1)}%)"
    puts ""

    result = DataIntegrity::GhostSessionCleanupService.new(account).call

    if result[:success]
      puts "Cleaned #{result[:conversions_cleaned]} conversions"
    else
      puts "ERROR: #{result[:errors].join(', ')}"
    end
  end
end
