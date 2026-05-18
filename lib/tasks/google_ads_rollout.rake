# frozen_string_literal: true

namespace :google_ads_rollout do
  desc "Enable GOOGLE_ADS_INTEGRATION for every paid account. Idempotent. Set DRY_RUN=true to preview."
  task enable_for_paid_accounts: :environment do
    flag = FeatureFlags::GOOGLE_ADS_INTEGRATION
    dry_run = ENV["DRY_RUN"] == "true"

    enabled = []
    already_on = []

    Account.joins(:plan).merge(Plan.paid).find_each do |account|
      if account.feature_enabled?(flag)
        already_on << account
      else
        account.enable_feature!(flag) unless dry_run
        enabled << account
      end
    end

    verb = dry_run ? "[DRY RUN] would enable" : "Enabled"
    enabled.each { |a| puts "#{verb} #{flag} for #{a.prefix_id} (#{a.name})" }

    puts "---"
    puts "#{dry_run ? 'Would enable' : 'Enabled'}: #{enabled.size}"
    puts "Already on: #{already_on.size}"
    puts "Total paid accounts: #{enabled.size + already_on.size}"
  end
end
