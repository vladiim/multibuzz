# frozen_string_literal: true

namespace :dev do
  desc "Generate LTV test data with varied timestamps for testing avg_duration calculations"
  task generate_ltv_data: :environment do
    unless Rails.env.development?
      puts "This task is only available in development environment"
      exit 1
    end

    account_slug = ENV["ACCOUNT_SLUG"]
    customer_count = (ENV["CUSTOMERS"] || 25).to_i
    clear_existing = ENV["CLEAR"] == "true"
    seed = ENV["SEED"]&.to_i
    production_mode = ENV["PRODUCTION"] == "true"

    unless account_slug
      puts "Usage: bin/rails dev:generate_ltv_data ACCOUNT_SLUG=your-account [CUSTOMERS=25] [CLEAR=true] [SEED=12345] [PRODUCTION=true]"
      puts ""
      puts "Options:"
      puts "  ACCOUNT_SLUG - Your account slug (required)"
      puts "  CUSTOMERS    - Number of customers to generate (default: 25)"
      puts "  CLEAR        - Clear existing test data first (default: false)"
      puts "  SEED         - Random seed for reproducible data"
      puts "  PRODUCTION   - Generate as production data, not test data (default: false)"
      exit 1
    end

    account = Account.find_by(slug: account_slug)
    unless account
      puts "Account not found: #{account_slug}"
      exit 1
    end

    generator = Dev::LtvDataGenerator.new(
      account,
      customer_count: customer_count,
      clear_existing: clear_existing,
      seed: seed,
      production_mode: production_mode
    )
    generator.call
  end

  desc "Generate ad spend seed data for an account"
  task generate_spend_data: :environment do
    unless Rails.env.development?
      puts "This task is only available in development environment"
      exit 1
    end

    account_slug = ENV["ACCOUNT_SLUG"]
    days = (ENV["DAYS"] || 90).to_i
    clear_existing = ENV["CLEAR"] == "true"
    seed = ENV["SEED"]&.to_i

    unless account_slug
      puts "Usage: bin/rails dev:generate_spend_data ACCOUNT_SLUG=acme-inc [DAYS=90] [CLEAR=true] [SEED=42]"
      exit 1
    end

    account = Account.find_by(slug: account_slug)
    unless account
      puts "Account not found: #{account_slug}"
      exit 1
    end

    Dev::SpendDataGenerator.new(account, days: days, clear_existing: clear_existing, seed: seed).call
  end

  desc "Clear all test data for an account"
  task clear_test_data: :environment do
    unless Rails.env.development?
      puts "This task is only available in development environment"
      exit 1
    end

    account_slug = ENV["ACCOUNT_SLUG"]

    unless account_slug
      puts "Usage: bin/rails dev:clear_test_data ACCOUNT_SLUG=your-account"
      exit 1
    end

    account = Account.find_by(slug: account_slug)
    unless account
      puts "Account not found: #{account_slug}"
      exit 1
    end

    puts "Clearing test data for: #{account.name}"

    ActiveRecord::Base.transaction do
      # Delete in FK-safe order (children before parents)
      credits_count = account.attribution_credits.where(is_test: true).delete_all
      conversions_count = account.conversions.where(is_test: true).delete_all
      events_count = account.events.where(is_test: true).delete_all
      sessions_count = account.sessions.where(is_test: true).delete_all

      # Visitors - only delete if no remaining non-test data references them
      test_visitors = account.visitors.where(is_test: true)
      safe_visitors = test_visitors.where.not(
        id: account.conversions.where(is_test: false).select(:visitor_id)
      ).where.not(
        id: account.sessions.where(is_test: false).select(:visitor_id)
      )
      visitors_count = safe_visitors.delete_all

      # Identities - only delete if no remaining conversions/visitors reference them
      test_identities = account.identities.where(is_test: true)
      safe_identities = test_identities
        .where.not(id: account.conversions.where.not(identity_id: nil).select(:identity_id))
        .where.not(id: account.visitors.where.not(identity_id: nil).select(:identity_id))
      identities_count = safe_identities.delete_all

      puts "Deleted:"
      puts "  #{credits_count} attribution credits"
      puts "  #{conversions_count} conversions"
      puts "  #{events_count} events"
      puts "  #{sessions_count} sessions"
      puts "  #{visitors_count} visitors"
      puts "  #{identities_count} identities"
    end

    puts "Done!"
  end
end

module Dev
  class LtvDataGenerator
    # Use string constants directly to avoid load-order issues with rake
    PAID_SEARCH = "paid_search"
    ORGANIC_SEARCH = "organic_search"
    PAID_SOCIAL = "paid_social"
    EMAIL = "email"
    DIRECT = "direct"

    CHANNELS = [ PAID_SEARCH, ORGANIC_SEARCH, PAID_SOCIAL, EMAIL, DIRECT ].freeze

    CHANNEL_WEIGHTS = {
      PAID_SEARCH => 0.30,
      ORGANIC_SEARCH => 0.25,
      PAID_SOCIAL => 0.20,
      EMAIL => 0.15,
      DIRECT => 0.10
    }.freeze

    UTM_SOURCES = {
      PAID_SEARCH => %w[google bing],
      ORGANIC_SEARCH => %w[google bing duckduckgo],
      PAID_SOCIAL => %w[facebook instagram linkedin],
      EMAIL => %w[newsletter drip mailchimp],
      DIRECT => [ nil ]
    }.freeze

    # Revenue patterns for different customer types
    CUSTOMER_PROFILES = [
      { type: :one_time, weight: 0.30, purchase_count: 1..1, revenue_range: 29..199 },
      { type: :returning, weight: 0.40, purchase_count: 2..4, revenue_range: 49..299 },
      { type: :loyal, weight: 0.20, purchase_count: 5..10, revenue_range: 99..499 },
      { type: :whale, weight: 0.10, purchase_count: 8..20, revenue_range: 199..999 }
    ].freeze

    def initialize(account, customer_count:, clear_existing: false, seed: nil, production_mode: false)
      @account = account
      @customer_count = customer_count
      @clear_existing = clear_existing
      @random = seed ? Random.new(seed) : Random.new
      @stats = Hash.new(0)
      @production_mode = production_mode
    end

    def call
      clear_data if @clear_existing

      mode_label = @production_mode ? "production" : "test"
      puts "Generating LTV #{mode_label} data for: #{@account.name}"
      puts "  Customers: #{@customer_count}"
      puts "  Mode: #{mode_label} (is_test: #{is_test_flag})"
      puts ""

      ActiveRecord::Base.transaction do
        generate_customers
      end

      print_summary
    end

    private

    attr_reader :account, :customer_count, :random, :stats

    def is_test_flag
      !@production_mode
    end

    def clear_data
      mode_label = @production_mode ? "production" : "test"
      puts "Clearing existing #{mode_label} data..."

      # Delete in FK-safe order (children before parents)
      # 1. Attribution credits (depends on conversions)
      credits = account.attribution_credits.where(is_test: is_test_flag).delete_all
      puts "  Deleted #{credits} attribution credits"

      # 2. Conversions (depends on visitors, identities)
      conversions = account.conversions.where(is_test: is_test_flag).delete_all
      puts "  Deleted #{conversions} conversions"

      # 3. Events (depends on sessions, visitors)
      events = account.events.where(is_test: is_test_flag).delete_all
      puts "  Deleted #{events} events"

      # 4. Sessions (depends on visitors)
      sessions = account.sessions.where(is_test: is_test_flag).delete_all
      puts "  Deleted #{sessions} sessions"

      # 5. Visitors - only delete if they have no remaining data from opposite mode
      target_visitors = account.visitors.where(is_test: is_test_flag)
      opposite_test_flag = !is_test_flag
      safe_to_delete = target_visitors.where.not(
        id: account.conversions.where(is_test: opposite_test_flag).select(:visitor_id)
      ).where.not(
        id: account.sessions.where(is_test: opposite_test_flag).select(:visitor_id)
      )
      visitors = safe_to_delete.delete_all
      puts "  Deleted #{visitors} visitors"

      # 6. Identities - only delete if no remaining conversions OR visitors reference them
      target_identities = account.identities.where(is_test: is_test_flag)
      safe_identities = target_identities
        .where.not(id: account.conversions.where.not(identity_id: nil).select(:identity_id))
        .where.not(id: account.visitors.where.not(identity_id: nil).select(:identity_id))
      identities = safe_identities.delete_all
      puts "  Deleted #{identities} identities"

      puts ""
    end

    def generate_customers
      customer_count.times do |i|
        print "\rGenerating customer #{i + 1}/#{customer_count}..."
        generate_customer(i)
      end
      puts "\rGenerating customer #{customer_count}/#{customer_count}... Done!"
    end

    def generate_customer(index)
      profile = select_customer_profile

      # Acquisition spread across last 12 months for cohort analysis
      # 70% in last 6 months, 30% in months 7-12
      acquisition_days_ago = if random.rand < 0.7
        random.rand(7..180)   # Last 6 months
      else
        random.rand(181..365) # 6-12 months ago
      end
      acquisition_time = acquisition_days_ago.days.ago + random.rand(0..86_400).seconds

      # Create identity (customer)
      identity = create_identity(index, acquisition_time)

      # Create visitor for this customer
      visitor = create_visitor(index, acquisition_time)
      visitor.update!(identity: identity)

      # Generate sessions before acquisition (awareness phase)
      pre_acquisition_sessions = generate_pre_acquisition_sessions(visitor, acquisition_time)

      # Create acquisition conversion (first purchase/signup)
      # The conversion session is the last one, but journey includes ALL sessions
      acquisition_session = pre_acquisition_sessions.last || create_session(visitor, acquisition_time)
      all_journey_sessions = pre_acquisition_sessions.any? ? pre_acquisition_sessions : [ acquisition_session ]
      create_acquisition_conversion(identity, visitor, acquisition_session, all_journey_sessions, acquisition_time, profile)

      # Generate repeat purchases based on profile
      purchase_count = random.rand(profile[:purchase_count])
      if purchase_count > 1
        generate_repeat_purchases(identity, visitor, acquisition_time, purchase_count - 1, profile)
      end

      stats[:customers] += 1
      @profile_counts ||= Hash.new(0)
      @profile_counts[profile[:type]] += 1
    end

    def select_customer_profile
      roll = random.rand
      cumulative = 0.0

      CUSTOMER_PROFILES.each do |profile|
        cumulative += profile[:weight]
        return profile if roll < cumulative
      end

      CUSTOMER_PROFILES.last
    end

    def create_identity(index, first_seen)
      mode_prefix = @production_mode ? "prod" : "test"
      account.identities.create!(
        external_id: "#{mode_prefix}_customer_#{index}_#{random.rand(100_000)}",
        traits: { plan: %w[free starter pro].sample(random: random) },
        first_identified_at: first_seen,
        last_identified_at: Time.current,
        is_test: is_test_flag
      )
    end

    def create_visitor(index, first_seen)
      mode_prefix = @production_mode ? "prod" : "test"
      account.visitors.create!(
        visitor_id: "#{mode_prefix}_vis_#{index}_#{random.rand(100_000)}",
        first_seen_at: first_seen - random.rand(1..7).days,
        last_seen_at: Time.current,
        is_test: is_test_flag
      )
    end

    def generate_pre_acquisition_sessions(visitor, acquisition_time)
      session_count = random.rand(1..5)
      sessions = []

      session_count.times do |_i|
        days_before = random.rand(1..14)
        session_time = acquisition_time - days_before.days + random.rand(0..86_400).seconds
        sessions << create_session(visitor, session_time)
      end

      sessions.sort_by(&:started_at)
    end

    def create_session(visitor, started_at)
      channel = weighted_random_channel
      utm_source = UTM_SOURCES[channel]&.sample(random: random)

      session = account.sessions.create!(
        visitor: visitor,
        session_id: SecureRandom.uuid,
        started_at: started_at,
        ended_at: started_at + random.rand(60..1800).seconds,
        page_view_count: random.rand(1..10),
        channel: channel,
        initial_utm: build_utm(channel, utm_source),
        is_test: is_test_flag,
        last_activity_at: started_at + random.rand(60..1800).seconds
      )

      # Create page_view event for the session
      account.events.create!(
        visitor: visitor,
        session_id: session.id,
        event_type: "page_view",
        occurred_at: started_at,
        properties: {
          url: "https://example.com/#{%w[pricing features about signup].sample(random: random)}",
          host: "example.com",
          path: "/#{%w[pricing features about signup].sample(random: random)}"
        },
        is_test: is_test_flag
      )

      stats[:sessions] += 1
      session
    end

    def build_utm(channel, source)
      return {} unless source

      {
        utm_source: source,
        utm_medium: channel_to_medium(channel),
        utm_campaign: "test_#{channel}"
      }.compact
    end

    def channel_to_medium(channel)
      case channel
      when PAID_SEARCH then "cpc"
      when PAID_SOCIAL then "paid_social"
      when EMAIL then "email"
      else nil
      end
    end

    def create_acquisition_conversion(identity, visitor, session, journey_sessions, acquisition_time, profile)
      revenue = random.rand(profile[:revenue_range])

      conversion = account.conversions.create!(
        visitor: visitor,
        identity: identity,
        session_id: session.id,
        conversion_type: "purchase",
        revenue: revenue,
        converted_at: acquisition_time,
        is_acquisition: true,
        journey_session_ids: journey_sessions.map(&:id),
        is_test: is_test_flag
      )

      create_attribution_credit(conversion, session)
      stats[:conversions] += 1
      stats[:revenue] += revenue
    end

    def generate_repeat_purchases(identity, visitor, acquisition_time, count, profile)
      # Customer lifespan from acquisition to now
      max_days_since_acquisition = ((Time.current - acquisition_time) / 1.day).to_i
      return if max_days_since_acquisition < 30

      # Spread purchases across lifecycle months (M1, M2, M3, etc.)
      # Each purchase targets a different month after acquisition
      count.times do |i|
        # Target a specific lifecycle month (M1=30-59 days, M2=60-89 days, etc.)
        target_month = i + 1
        min_days = target_month * 30
        max_days = [ min_days + 29, max_days_since_acquisition ].min

        # Skip if this month is in the future
        next if min_days > max_days_since_acquisition

        days_after = random.rand(min_days..max_days)
        purchase_time = acquisition_time + days_after.days + random.rand(0..86_400).seconds

        # Create a new session for this purchase
        session = create_session(visitor, purchase_time - random.rand(1..60).minutes)

        revenue = random.rand(profile[:revenue_range])

        conversion = account.conversions.create!(
          visitor: visitor,
          identity: identity,
          session_id: session.id,
          conversion_type: "payment",
          revenue: revenue,
          converted_at: purchase_time,
          is_acquisition: false,
          journey_session_ids: [ session.id ],
          is_test: is_test_flag
        )

        create_attribution_credit(conversion, session)
        stats[:conversions] += 1
        stats[:revenue] += revenue
      end
    end

    def create_attribution_credit(conversion, session)
      model = default_attribution_model
      return unless model

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: model,
        session_id: session.id,
        channel: session.channel,
        credit: 1.0,
        revenue_credit: conversion.revenue,
        utm_source: session.initial_utm&.dig("utm_source"),
        utm_medium: session.initial_utm&.dig("utm_medium"),
        utm_campaign: session.initial_utm&.dig("utm_campaign"),
        is_test: is_test_flag,
        model_version: model.version
      )

      stats[:credits] += 1
    end

    def default_attribution_model
      @default_attribution_model ||= account.attribution_models.active.find_by(is_default: true) ||
        account.attribution_models.active.first
    end

    def weighted_random_channel
      roll = random.rand
      cumulative = 0.0

      CHANNEL_WEIGHTS.each do |channel, weight|
        cumulative += weight
        return channel if roll < cumulative
      end

      CHANNELS.last
    end

    def print_summary
      puts ""
      puts "=== SUMMARY ==="
      puts "Created:"
      puts "  #{stats[:customers]} customers (identities)"
      puts "  #{stats[:sessions]} sessions"
      puts "  #{stats[:conversions]} conversions"
      puts "  #{stats[:credits]} attribution credits"
      puts "  Total revenue: $#{stats[:revenue].round(2)}"
      puts ""
      puts "Customer breakdown:"
      @profile_counts&.each do |type, count|
        puts "  #{type}: #{count}"
      end
      puts ""
      puts "Expected LTV metrics:"
      avg_purchases = stats[:conversions].to_f / stats[:customers]
      avg_clv = stats[:revenue].to_f / stats[:customers]
      puts "  Avg purchases per customer: #{avg_purchases.round(2)}"
      puts "  Avg CLV: $#{avg_clv.round(2)}"
      puts ""
      puts "To view in dashboard, filter by 'Test data' or enable test data view."
    end
  end

  class SpendDataGenerator
    PAID_CHANNELS = {
      "paid_search" => { campaign_type: "SEARCH", cpm: 15_000, ctr: 0.05 },
      "paid_social" => { campaign_type: "SOCIAL", cpm: 8_000, ctr: 0.012 },
      "display" => { campaign_type: "DISPLAY", cpm: 3_000, ctr: 0.004 },
      "video" => { campaign_type: "VIDEO", cpm: 10_000, ctr: 0.015 }
    }.freeze

    CAMPAIGNS = {
      "paid_search" => [
        { id: "100001", name: "Brand Search", weight: 0.45 },
        { id: "100002", name: "Non-Brand Search", weight: 0.35 },
        { id: "100003", name: "Competitor Search", weight: 0.20 }
      ],
      "paid_social" => [
        { id: "200001", name: "Prospecting LAL", weight: 0.50 },
        { id: "200002", name: "Retargeting", weight: 0.30 },
        { id: "200003", name: "Brand Awareness", weight: 0.20 }
      ],
      "display" => [
        { id: "300001", name: "Remarketing Display", weight: 0.60 },
        { id: "300002", name: "Contextual Display", weight: 0.40 }
      ],
      "video" => [
        { id: "400001", name: "YouTube TrueView", weight: 0.70 },
        { id: "400002", name: "YouTube Bumper", weight: 0.30 }
      ]
    }.freeze

    DEVICES = %w[DESKTOP MOBILE TABLET].freeze
    DEVICE_WEIGHTS = [ 0.45, 0.45, 0.10 ].freeze
    CURRENCY = "USD"

    # Daily budget per channel (micros) — adds up to ~$800/day total
    DAILY_BUDGETS = {
      "paid_search" => 350_000_000,
      "paid_social" => 250_000_000,
      "display" => 100_000_000,
      "video" => 100_000_000
    }.freeze

    def initialize(account, days:, clear_existing: false, seed: nil)
      @account = account
      @days = days
      @clear_existing = clear_existing
      @random = seed ? Random.new(seed) : Random.new
      @stats = Hash.new(0)
    end

    def call
      setup_connection
      clear_data if @clear_existing

      puts "Generating #{@days} days of spend data for: #{@account.name}"
      puts "  Daily budget: ~$#{DAILY_BUDGETS.values.sum / 1_000_000}"
      puts ""

      ActiveRecord::Base.transaction { generate_spend_records }

      print_summary
    end

    private

    attr_reader :account, :random, :stats

    def setup_connection
      @connection = account.ad_platform_connections.find_or_create_by!(
        platform: :google_ads,
        platform_account_id: "8515486033"
      ) do |c|
        c.platform_account_name = "#{account.name} — Google Ads"
        c.currency = CURRENCY
        c.status = :connected
        c.access_token = "seed_token"
        c.refresh_token = "seed_refresh"
        c.token_expires_at = 1.year.from_now
      end
      puts "Connection: #{@connection.platform_account_name} (#{@connection.prefix_id})"
    end

    def clear_data
      count = account.ad_spend_records.delete_all
      puts "Cleared #{count} existing spend records"
    end

    def generate_spend_records
      @days.times do |i|
        date = i.days.ago.to_date
        print "\rGenerating #{date}..."
        generate_day(date)
      end
      puts "\rGenerated #{@days} days of spend data. Done!"
    end

    def generate_day(date)
      PAID_CHANNELS.each do |channel, config|
        CAMPAIGNS[channel].each do |campaign|
          generate_campaign_day(date, channel, config, campaign)
        end
      end
    end

    # Platform ROAS by channel — Google's self-reported numbers
    # (deliberately higher than attributed, ~30-50% inflated via view-through)
    PLATFORM_ROAS = {
      "paid_search" => 4.5,
      "paid_social" => 2.8,
      "display" => 1.6,
      "video" => 2.0
    }.freeze

    def generate_campaign_day(date, channel, config, campaign)
      budget_share = DAILY_BUDGETS[channel] * campaign[:weight]
      rows = []

      24.times do |hour|
        hour_weight = hour_distribution(hour)
        weighted_device.each do |device, device_weight|
          spend = (budget_share * hour_weight * device_weight * variance).to_i
          next if spend.zero?

          impressions = [(spend.to_f / config[:cpm] * 1000 * variance).to_i, 1].max
          clicks = [impressions * config[:ctr] * variance, 0].max.to_i
          platform_value = (spend * PLATFORM_ROAS[channel] * variance).to_i
          platform_conversions = (clicks * 0.02 * variance * 1_000_000).to_i

          rows << {
            account_id: account.id,
            ad_platform_connection_id: @connection.id,
            spend_date: date,
            spend_hour: hour,
            channel: channel,
            platform_campaign_id: campaign[:id],
            campaign_name: campaign[:name],
            campaign_type: config[:campaign_type],
            device: device,
            spend_micros: spend,
            currency: CURRENCY,
            impressions: impressions,
            clicks: clicks,
            platform_conversions_micros: platform_conversions,
            platform_conversion_value_micros: platform_value,
            is_test: false,
            created_at: Time.current,
            updated_at: Time.current
          }
          stats[:records] += 1
          stats[:spend] += spend
        end
      end

      AdSpendRecord.insert_all(rows) if rows.any?
    end

    def hour_distribution(hour)
      case hour
      when 0..5 then 0.01
      when 6..8 then 0.03
      when 9..11 then 0.06
      when 12..14 then 0.07
      when 15..17 then 0.06
      when 18..20 then 0.05
      when 21..23 then 0.03
      end
    end

    def weighted_device
      DEVICES.zip(DEVICE_WEIGHTS)
    end

    def variance
      0.7 + random.rand * 0.6
    end

    def print_summary
      puts ""
      puts "=== SPEND SEED SUMMARY ==="
      puts "  Records created: #{stats[:records]}"
      puts "  Total spend: $#{(stats[:spend].to_f / 1_000_000).round(2)}"
      puts "  Date range: #{@days.days.ago.to_date} → #{Date.current}"
      puts "  Campaigns: #{CAMPAIGNS.values.flatten.size}"
      puts "  Channels: #{PAID_CHANNELS.keys.join(', ')}"
      puts ""
      puts "Run MetricsService:"
      puts "  bin/rails runner \"result = SpendIntelligence::MetricsService.new(Account.find_by(slug: '#{account.slug}'), { date_range: '30d' }).call; pp result[:data][:totals]\""
    end
  end
end
