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

    puts "\nAPI usage today: #{AdPlatforms::ApiUsageTracker.current_usage(:google_ads)}/#{AdPlatforms::ApiUsageTracker.daily_limit_for(:google_ads)}"
  end

  namespace :meta do
    desc "Verify Meta Ads API access by listing the connected ad accounts via /me/adaccounts"
    task verify_credentials: :environment do
      connection = AdPlatformConnection.active_connections.where(platform: :meta_ads).first

      abort "No active Meta Ads connections found. Connect an account first." unless connection

      puts "Testing Meta Ads API with connection: #{connection.platform_account_name} (#{connection.platform_account_id})"

      if connection.token_expired?
        puts "Token expired — refreshing..."
        result = AdPlatforms::Meta::TokenRefresher.new(connection).call
        abort "Token refresh failed: #{result[:errors]&.join(', ')}" unless result[:success]
        puts "Token refreshed."
      end

      puts "Calling /me/adaccounts..."
      client = AdPlatforms::Meta::ApiClient.new(access_token: connection.access_token)
      body = client.get(
        AdPlatforms::Meta::AD_ACCOUNTS_URI,
        query: { fields: AdPlatforms::Meta::AD_ACCOUNT_FIELDS, limit: 25 }
      )

      if body["error"]
        puts "FAILED: #{body.dig('error', 'message') || body.inspect}"
        abort "Meta Ads API call failed. Check app_id/app_secret and the connection's access token."
      end

      accounts = AdPlatforms::Meta::ListAdAccountsParser.new(body: body).accounts
      puts "Access VERIFIED. #{accounts.size} active ad account(s):"
      accounts.first(10).each { |a| puts "  #{a[:id]} — #{a[:name]} (#{a[:currency]})" }
      puts "  ... (#{accounts.size - 10} more)" if accounts.size > 10

      puts "\nAPI usage today: #{AdPlatforms::ApiUsageTracker.current_usage(:meta_ads)}/#{AdPlatforms::ApiUsageTracker.daily_limit_for(:meta_ads)}"
    end
  end
end
