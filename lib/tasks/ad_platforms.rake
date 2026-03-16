# frozen_string_literal: true

namespace :ad_platforms do
  desc "Verify Google Ads API Basic Access by making a live ListAccessibleCustomers call"
  task verify_basic_access: :environment do
    connection = AdPlatformConnection.active_connections.where(platform: :google_ads).first

    abort "No active Google Ads connections found. Connect an account first." unless connection

    puts "Testing Google Ads API with connection: #{connection.platform_account_name} (#{connection.platform_account_id})"
    puts "Developer token: #{AdPlatforms::Google.credentials.fetch(:developer_token)[0..5]}..."

    # Refresh token if expired
    if connection.token_expired?
      puts "Token expired — refreshing..."
      result = AdPlatforms::Google::TokenRefresher.new(connection).call
      abort "Token refresh failed: #{result[:errors]&.join(', ')}" unless result[:success]
      connection.update!(access_token: result[:access_token], token_expires_at: result[:expires_at])
      puts "Token refreshed."
    end

    # Make a real API call
    puts "Calling ListAccessibleCustomers..."
    client = AdPlatforms::Google::ApiClient.new(access_token: connection.access_token)
    response = client.get(AdPlatforms::Google::LIST_CUSTOMERS_URI)

    if response.is_a?(Net::HTTPSuccess)
      body = JSON.parse(response.body)
      customers = body.fetch(AdPlatforms::Google::FIELD_RESOURCE_NAMES, [])
      puts "Basic Access VERIFIED. #{customers.size} accessible customer(s):"
      customers.each { |c| puts "  #{c}" }
    else
      puts "FAILED (HTTP #{response.code}): #{response.body}"
      abort "Google Ads API call failed. Check developer token and credentials."
    end

    puts "\nAPI usage today: #{AdPlatforms::Google::ApiUsageTracker.current_usage}/#{AdPlatforms::Google::ApiUsageTracker::DAILY_OPERATION_LIMIT}"
  end
end
