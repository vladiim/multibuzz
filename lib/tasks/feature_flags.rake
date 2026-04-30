# frozen_string_literal: true

namespace :feature_flags do
  desc "Enable a feature flag for an account: ACCT=acct_xxx FLAG=meta_ads_integration"
  task enable: :environment do
    flag = require_known_flag
    account = require_account

    account.enable_feature!(flag)
    puts "Enabled #{flag} for #{account.name} (#{account.prefix_id})."
  end

  desc "Disable a feature flag for an account: ACCT=acct_xxx FLAG=meta_ads_integration"
  task disable: :environment do
    flag = require_known_flag
    account = require_account

    account.disable_feature!(flag)
    puts "Disabled #{flag} for #{account.name} (#{account.prefix_id})."
  end

  desc "List all flags for an account: ACCT=acct_xxx"
  task list: :environment do
    account = require_account
    flags = account.feature_flags.pluck(:flag_name)

    if flags.empty?
      puts "No flags enabled for #{account.name} (#{account.prefix_id})."
    else
      puts "Flags for #{account.name} (#{account.prefix_id}):"
      flags.each { |name| puts "  - #{name}" }
    end
  end

  desc "List all accounts with a given flag: FLAG=meta_ads_integration"
  task accounts: :environment do
    flag = require_known_flag
    accounts = Account.joins(:feature_flags).where(account_feature_flags: { flag_name: flag }).distinct

    if accounts.empty?
      puts "No accounts have #{flag} enabled."
    else
      puts "Accounts with #{flag} enabled:"
      accounts.each { |account| puts "  - #{account.prefix_id}  #{account.name}" }
    end
  end
end

def require_known_flag
  flag = ENV["FLAG"].to_s
  abort "FLAG required (one of: #{FeatureFlags::ALL.join(', ')})" if flag.empty?
  abort "Unknown flag: #{flag}. Known flags: #{FeatureFlags::ALL.join(', ')}" unless FeatureFlags::ALL.include?(flag)

  flag
end

def require_account
  prefix = ENV["ACCT"].to_s
  abort "ACCT required (e.g. ACCT=acct_xxx)" if prefix.empty?

  account = Account.find_by_prefix_id(prefix)
  abort "Account not found: #{prefix}" unless account

  account
end
