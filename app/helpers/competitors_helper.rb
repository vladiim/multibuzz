# frozen_string_literal: true

module CompetitorsHelper
  # Load all competitors from YAML
  def all_competitors
    @all_competitors ||= load_competitors_data
  end

  # Load mbuzz data
  def mbuzz_data
    @mbuzz_data ||= competitors_yaml["mbuzz"]
  end

  # Get competitor by slug
  def competitor(slug)
    all_competitors.find { |c| c["slug"] == slug }
  end

  # Get competitors excluding one (for alternatives pages)
  def competitors_except(slug)
    all_competitors.reject { |c| c["slug"] == slug }
  end

  # Get competitor logo path (handles PNG vs SVG)
  def competitor_logo_path(slug)
    # Use Google's cleaner icon for GA4
    slug = "google" if slug == "ga4"
    png_path = Rails.root.join("public/images/competitors/#{slug}/logo.png")
    File.exist?(png_path) ? "/images/competitors/#{slug}/logo.png" : "/images/competitors/#{slug}/logo.svg"
  end

  # Get alternatives article path for a competitor
  def competitor_alternatives_path(slug)
    "/articles/#{slug}-alternatives"
  end

  # Check if alternatives article exists
  def has_alternatives_article?(slug)
    File.exist?(Rails.root.join("app/content/articles/comparisons/#{slug}-alternatives.md.erb"))
  end

  # Format price for display
  def format_competitor_price(competitor)
    pricing = competitor["pricing"]
    return "Custom" unless pricing

    starting = pricing["starting"]
    return "Free" if starting == 0
    return "Custom" if starting.nil?

    currency = pricing["currency"] || "USD"
    symbol = currency == "GBP" ? "£" : "$"
    "#{symbol}#{starting}/mo"
  end

  # Get price tier for filtering
  def price_tier(competitor)
    starting = competitor.dig("pricing", "starting")
    return "free" if starting == 0 || competitor.dig("pricing", "has_free_tier")
    return "enterprise" if starting.nil?
    return "budget" if starting < 200
    return "mid" if starting < 1000
    return "premium" if starting < 2500
    "enterprise"
  end

  # Build feature list for data attributes
  def competitor_features_string(competitor)
    features = []
    f = competitor["features"] || {}

    features << "free_tier" if competitor.dig("pricing", "has_free_tier")
    features << "custom_models" if f["custom_models"]
    features << "server_side" if f["server_side"]
    features << "ltv_tracking" if f["ltv_tracking"]
    features << "view_through" if f["view_through"]
    features << "mmm" if f["mmm_included"]
    features << "call_tracking" if f["call_tracking"]
    features << "incrementality" if f["incrementality"]

    features.join(",")
  end

  # Category display names
  def category_display_name(category)
    {
      "dtc" => "E-commerce / DTC",
      "b2b" => "B2B SaaS",
      "enterprise" => "Enterprise",
      "multi_channel" => "Multi-Channel",
      "lead_gen" => "Lead Generation",
      "unified" => "Unified Measurement",
      "free" => "Free Tools"
    }[category] || category.titleize
  end

  # Convert setup_time string to hours for filtering
  # Returns max hours for ranges (e.g., "1-2 weeks" returns 336)
  def setup_time_hours(competitor)
    setup_time = competitor.dig("features", "setup_time")
    return 9999 unless setup_time

    case setup_time.downcase
    when /minutes?$/, /^\d+\s*minutes?$/
      1
    when /hours?$/
      24
    when /1-2 weeks?/, /1 week/
      336
    when /2 weeks?/
      336
    when /2-4 weeks?/
      672
    when /4-8 weeks?/, /1-2 months?/
      1344
    when /3-6 months?/
      4320
    else
      9999
    end
  end

  # Display-friendly setup time
  def setup_time_display(competitor)
    competitor.dig("features", "setup_time") || "Custom"
  end

  # Get key feature badges for display (max 3 to keep it fair)
  # Returns array of hashes with :name, :bg_class, :text_class
  def key_feature_badges(competitor, max: 3)
    features = competitor["features"] || {}
    badges = []

    # Feature definitions with styling
    feature_defs = [
      { key: "custom_models", name: "Custom models", bg: "bg-indigo-100", text: "text-indigo-700" },
      { key: "server_side", name: "Server-side", bg: "bg-emerald-100", text: "text-emerald-700" },
      { key: "ltv_tracking", name: "LTV", bg: "bg-purple-100", text: "text-purple-700" },
      { key: "view_through", name: "View-through", bg: "bg-sky-100", text: "text-sky-700" },
      { key: "mmm_included", name: "MMM", bg: "bg-blue-100", text: "text-blue-700" },
      { key: "incrementality", name: "Incrementality", bg: "bg-teal-100", text: "text-teal-700" },
      { key: "call_tracking", name: "Calls", bg: "bg-amber-100", text: "text-amber-700" },
      { key: "journey_visualization", name: "Journey viz", bg: "bg-rose-100", text: "text-rose-700" }
    ]

    feature_defs.each do |fd|
      break if badges.size >= max
      next unless features[fd[:key]]

      badges << { name: fd[:name], bg_class: fd[:bg], text_class: fd[:text] }
    end

    badges
  end

  private

  def competitors_yaml
    @competitors_yaml ||= begin
      path = Rails.root.join("config/competitors.yml")
      YAML.safe_load(ERB.new(File.read(path)).result, permitted_classes: [ Symbol ])
    end
  end

  def load_competitors_data
    competitors = competitors_yaml["competitors"].map do |key, data|
      data.merge("key" => key)
    end

    # Add mbuzz to the list
    mbuzz = competitors_yaml["mbuzz"]
    if mbuzz
      competitors.unshift(mbuzz.merge("key" => "mbuzz"))
    end

    competitors
  end
end
