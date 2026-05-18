# frozen_string_literal: true

require "test_helper"

module Dashboard
  class SpendCsvExportServiceTest < ActiveSupport::TestCase
    # ==========================================
    # CSV structure
    # ==========================================

    test "returns CSV with the documented headers" do
      csv = export_and_parse

      assert_equal expected_headers, csv.headers
    end

    test "writes header-only CSV when no spend rows match" do
      AdSpendRecord.where(account: account).delete_all

      csv = export_and_parse

      assert_equal expected_headers, csv.headers
      assert_equal 0, csv.size
    end

    # ==========================================
    # Date range
    # ==========================================

    test "includes rows inside the requested date range" do
      csv = export_and_parse(service(date_range: "7d"))

      assert_predicate csv, :any?, "expected at least one row in default 7d range"
      assert csv.all? { |row| Date.parse(row["spend_date"]) >= 7.days.ago.to_date }
    end

    test "excludes rows outside the requested date range" do
      old_record = create_spend_record(spend_date: 90.days.ago.to_date)

      csv = export_and_parse(service(date_range: "7d"))

      assert csv.none? { |row| row["spend_date"] == old_record.spend_date.to_s },
        "row outside date range should be excluded"
    end

    # ==========================================
    # Channel filter
    # ==========================================

    test "filters by channels when given a non-ALL list" do
      csv = export_and_parse(service(channels: [ Channels::PAID_SEARCH ]))

      assert_predicate csv, :any?
      assert csv.all? { |row| row["channel"] == Channels::PAID_SEARCH }
    end

    test "includes all channels when channels param is ALL" do
      channels_in_export = export_and_parse.map { |row| row["channel"] }.uniq

      assert_includes channels_in_export, Channels::PAID_SEARCH
      assert_includes channels_in_export, "display"
    end

    # ==========================================
    # Test mode
    # ==========================================

    test "excludes test rows when test_mode is false" do
      csv = export_and_parse(service(test_mode: false))

      campaign_names = csv.map { |row| row["campaign_name"] }

      assert_not_includes campaign_names, "Test Campaign"
    end

    test "returns only test rows when test_mode is true" do
      csv = export_and_parse(service(test_mode: true))

      assert_predicate csv, :any?, "expected at least one test row"
      campaign_names = csv.map { |row| row["campaign_name"] }.uniq

      assert_equal [ "Test Campaign" ], campaign_names
    end

    # ==========================================
    # Account isolation
    # ==========================================

    test "never includes rows from another account" do
      csv = export_and_parse

      campaign_names = csv.map { |row| row["campaign_name"] }

      assert_not_includes campaign_names, "Beta Search",
        "should not leak account two's data into account one's export"
    end

    # ==========================================
    # Value rendering
    # ==========================================

    test "spend is rendered in major units, not micros" do
      csv = export_and_parse
      row = csv.find { |r| r["campaign_name"] == "Brand Search" && r["spend_date"] == Date.current.to_s }

      assert row, "expected today's Brand Search row"
      assert_equal "12.4", BigDecimal(row["spend"]).to_s("F")
    end

    test "platform_conversion_value rendered in major units" do
      csv = export_and_parse
      row = csv.find { |r| r["campaign_name"] == "Brand Search" && r["spend_date"] == Date.current.to_s }

      assert_equal "50.0", BigDecimal(row["platform_conversion_value"]).to_s("F")
    end

    test "platform_conversions rendered in major units" do
      csv = export_and_parse
      row = csv.find { |r| r["campaign_name"] == "Brand Search" && r["spend_date"] == Date.current.to_s }

      assert_equal "10.0", BigDecimal(row["platform_conversions"]).to_s("F")
    end

    test "platform column shows the joined connection platform" do
      csv = export_and_parse
      platforms = csv.map { |row| row["platform"] }.uniq

      assert_equal [ "google_ads" ], platforms
    end

    test "campaign_type and network_type come through" do
      csv = export_and_parse
      display_row = csv.find { |r| r["channel"] == "display" }

      assert display_row, "expected a display row"
      assert_equal "DISPLAY", display_row["campaign_type"]
      assert_equal "CONTENT", display_row["network_type"]
    end

    test "spend_hour comes through as integer" do
      csv = export_and_parse
      row = csv.find { |r| r["campaign_name"] == "Brand Search" && r["spend_date"] == Date.current.to_s }

      assert_equal "14", row["spend_hour"]
    end

    test "device comes through" do
      csv = export_and_parse
      display_row = csv.find { |r| r["channel"] == "display" }

      assert_equal "MOBILE", display_row["device"]
    end

    # ==========================================
    # Metadata
    # ==========================================

    test "metadata column is compact JSON when present" do
      tagged = create_spend_record(metadata: { "location" => "Sydney" })

      csv = export_and_parse
      row = csv.find { |r| r["campaign_name"] == tagged.campaign_name }

      assert row, "expected the tagged row"
      assert_equal({ "location" => "Sydney" }, JSON.parse(row["metadata"]))
    end

    test "metadata column is '{}' for untagged rows" do
      csv = export_and_parse
      row = csv.find { |r| r["campaign_name"] == "Brand Search" && r["spend_date"] == Date.current.to_s }

      assert_equal({}, JSON.parse(row["metadata"]))
    end

    private

    def expected_headers
      %w[
        spend_date channel platform campaign_name campaign_type network_type
        device spend_hour spend currency impressions clicks
        platform_conversions platform_conversion_value metadata
      ]
    end

    def service(date_range: "30d", channels: Channels::ALL, test_mode: false)
      filter_params = { date_range: date_range, channels: channels, test_mode: test_mode }
      Dashboard::SpendCsvExportService.new(account, filter_params)
    end

    def account
      @account ||= accounts(:one)
    end

    def google_ads_connection
      @google_ads_connection ||= ad_platform_connections(:google_ads)
    end

    def export_and_parse(svc = service)
      file = Tempfile.new([ "spend_export_test", ".csv" ])
      svc.write_to(file.path)
      CSV.parse(File.read(file.path), headers: true)
    ensure
      file&.close!
    end

    def create_spend_record(**overrides)
      defaults = {
        account: account,
        ad_platform_connection: google_ads_connection,
        spend_date: Date.current,
        spend_hour: 9,
        channel: Channels::PAID_SEARCH,
        platform_campaign_id: "campaign_#{SecureRandom.hex(3)}",
        campaign_name: "Generated #{SecureRandom.hex(3)}",
        spend_micros: 1_000_000,
        currency: "USD",
        impressions: 100,
        clicks: 5,
        is_test: false
      }
      AdSpendRecord.create!(defaults.merge(overrides))
    end
  end
end
