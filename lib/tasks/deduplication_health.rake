# frozen_string_literal: true

namespace :deduplication do
  desc "Check visitor/session deduplication health for PetPro360"
  task health: :environment do
    account = Account.find(2)

    puts "=" * 70
    puts "DEDUPLICATION HEALTH CHECK - #{account.name}"
    puts "Run: #{Time.current}"
    puts "=" * 70

    # Historical baseline dates (known bad period)
    pre_fix_range = Date.new(2025, 12, 29)..Date.new(2026, 1, 3).end_of_day

    # ================================================================
    # 1. CONCURRENT VISITOR CREATION (The key Turbo bug metric)
    # ================================================================
    puts "\n📊 CONCURRENT VISITOR CREATION (Turbo Duplicate Bug)"
    puts "-" * 70

    [
      ["Pre-fix baseline", pre_fix_range],
      ["Last 24 hours", 24.hours.ago..Time.current],
      ["Last 1 hour", 1.hour.ago..Time.current]
    ].each do |name, range|
      multi = Visitor.where(account: account, created_at: range)
        .group("DATE_TRUNC('second', created_at)")
        .having("COUNT(*) > 1")
        .count

      total = Visitor.where(account: account, created_at: range)
        .select("DISTINCT DATE_TRUNC('second', created_at)").count

      max = multi.values.max || 0
      pct = total > 0 ? (multi.count.to_f / total * 100).round(1) : 0

      status = if max > 3
        "❌ BUG ACTIVE"
      elsif max > 0
        "⚠️ Minor"
      else
        "✅ Fixed"
      end

      puts "#{name}:"
      puts "  Seconds with duplicates: #{multi.count}/#{total} (#{pct}%)"
      puts "  Max visitors per second: #{max} #{status}"
      puts ""
    end

    # ================================================================
    # 2. V/S RATIO TREND
    # ================================================================
    puts "\n📊 V/S RATIO TREND (Last 7 days)"
    puts "-" * 70
    puts "Date       | Visitors | Sessions | Ratio  | Status"
    puts "-" * 70

    (7.days.ago.to_date..Date.current).each do |date|
      range = date.beginning_of_day..date.end_of_day
      v = Visitor.where(account: account, created_at: range).count
      s = Session.where(account: account, started_at: range).count
      next if v == 0 && s == 0

      ratio = v.to_f / [s, 1].max
      status = ratio > 1.2 ? "⚠️ High" : "✅"

      puts format("%s | %8d | %8d | %6.3f | %s", date, v, s, ratio, status)
    end

    # ================================================================
    # 3. FINGERPRINT COVERAGE (Post-fix only)
    # ================================================================
    puts "\n\n📊 FINGERPRINT COVERAGE (Last 24h)"
    puts "-" * 70

    sessions_24h = Session.where(account: account).where("started_at > ?", 24.hours.ago)
    total = sessions_24h.count
    with_fp = sessions_24h.where.not(device_fingerprint: nil).count
    unique_fp = sessions_24h.where.not(device_fingerprint: nil).distinct.count(:device_fingerprint)

    puts "Sessions: #{total}"
    puts "With fingerprint: #{with_fp} (#{total > 0 ? (with_fp.to_f / total * 100).round(1) : 0}%)"
    puts "Unique fingerprints: #{unique_fp}"
    puts with_fp == total ? "✅ All sessions have fingerprints" : "⚠️ Some sessions missing fingerprints"

    # ================================================================
    # 4. VERDICT
    # ================================================================
    puts "\n\n" + "=" * 70
    puts "VERDICT"
    puts "=" * 70

    # Check last hour for concurrent creation
    last_hour_max = Visitor.where(account: account)
      .where("created_at > ?", 1.hour.ago)
      .group("DATE_TRUNC('second', created_at)")
      .having("COUNT(*) > 1")
      .count.values.max || 0

    if last_hour_max == 0
      puts "✅ DEDUPLICATION WORKING - No concurrent visitor creation in last hour"
    else
      puts "❌ DEDUPLICATION FAILING - #{last_hour_max} visitors created in single second"
    end

    puts "=" * 70
  end
end
