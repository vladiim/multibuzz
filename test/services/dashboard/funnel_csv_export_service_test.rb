# frozen_string_literal: true

require "test_helper"

module Dashboard
  class FunnelCsvExportServiceTest < ActiveSupport::TestCase
    setup do
      Session.where(account: account).update_all(channel: Channels::PAID_SEARCH)
    end

    # ==========================================
    # CSV structure tests
    # ==========================================

    test "returns CSV string with correct headers" do
      csv = export_and_parse

      assert_equal expected_headers, csv.headers
    end

    test "returns headers-only CSV when no data" do
      Session.where(account: account).delete_all

      csv = export_and_parse

      assert_equal expected_headers, csv.headers
      assert_equal 0, csv.size
    end

    # ==========================================
    # Visit rows
    # ==========================================

    test "visit rows have type visit and nil name" do
      csv = export_and_parse
      visits = csv.select { |row| row["type"] == FunnelStages::VISIT }

      assert_predicate visits, :any?, "expected at least one visit row"
      visits.each { |row| assert_nil row["name"] }
    end

    test "visit rows use session started_at as date" do
      session = create_session(started_at: 3.days.ago)

      csv = export_and_parse
      visit = csv.find { |row| row["type"] == FunnelStages::VISIT && row["date"] == 3.days.ago.to_date.to_s }

      assert visit, "expected visit row with correct date"
    end

    test "visit rows include channel from session" do
      create_session(channel: Channels::EMAIL)

      csv = export_and_parse
      email_visit = csv.find { |row| row["type"] == FunnelStages::VISIT && row["channel"] == Channels::EMAIL }

      assert email_visit, "expected visit row with email channel"
    end

    test "visit rows include UTM from session initial_utm" do
      create_session(initial_utm: { "utm_source" => "bing", "utm_medium" => "display", "utm_campaign" => "winter" })

      csv = export_and_parse
      visit = csv.find { |row| row["type"] == FunnelStages::VISIT && row["utm_source"] == "bing" }

      assert visit, "expected visit with UTM data"
      assert_equal "display", visit["utm_medium"]
      assert_equal "winter", visit["utm_campaign"]
    end

    # ==========================================
    # Event rows
    # ==========================================

    test "event rows have type event and event_type as name" do
      create_event(event_type: "add_to_cart")

      csv = export_and_parse
      event = csv.find { |row| row["type"] == FunnelStages::EVENT && row["name"] == "add_to_cart" }

      assert event, "expected event row with name=add_to_cart"
    end

    test "event rows use occurred_at as date" do
      create_event(occurred_at: 2.days.ago)

      csv = export_and_parse
      event = csv.find { |row| row["type"] == FunnelStages::EVENT && row["date"] == 2.days.ago.to_date.to_s }

      assert event, "expected event row with correct date"
    end

    test "event rows get channel from joined session" do
      session = create_session(channel: Channels::ORGANIC_SEARCH)
      create_event(session: session)

      csv = export_and_parse
      event = csv.find { |row| row["type"] == FunnelStages::EVENT && row["channel"] == Channels::ORGANIC_SEARCH }

      assert event, "expected event row with session channel"
    end

    test "event rows get UTM from joined session initial_utm" do
      session = create_session(initial_utm: { "utm_source" => "fb", "utm_medium" => "social", "utm_campaign" => "launch" })
      create_event(session: session)

      csv = export_and_parse
      event = csv.find { |row| row["type"] == FunnelStages::EVENT && row["utm_source"] == "fb" }

      assert event, "expected event with session UTM"
      assert_equal "social", event["utm_medium"]
      assert_equal "launch", event["utm_campaign"]
    end

    test "event rows include properties as JSON" do
      create_event(properties: { "page" => "/checkout", "url" => "https://example.com" })

      csv = export_and_parse
      event = csv.find { |row| row["type"] == FunnelStages::EVENT }

      assert_includes event["properties"], "checkout"
    end

    # ==========================================
    # Conversion rows
    # ==========================================

    test "conversion rows have type conversion and conversion_type as name" do
      create_conversion(conversion_type: "purchase")

      csv = export_and_parse
      conversion = csv.find { |row| row["type"] == FunnelStages::CONVERSION && row["name"] == "purchase" }

      assert conversion, "expected conversion row with name=purchase"
    end

    test "conversion rows use converted_at as date" do
      create_conversion(converted_at: 4.days.ago)

      csv = export_and_parse
      conversion = csv.find { |row| row["type"] == FunnelStages::CONVERSION && row["date"] == 4.days.ago.to_date.to_s }

      assert conversion, "expected conversion row with correct date"
    end

    test "conversion rows include revenue, currency, is_acquisition" do
      create_conversion(revenue: 99.99, currency: "EUR", is_acquisition: true, identity: identities(:one))

      csv = export_and_parse
      conversion = csv.find { |row| row["type"] == FunnelStages::CONVERSION }

      assert_equal "99.99", conversion["revenue"]
      assert_equal "EUR", conversion["currency"]
      assert_equal "true", conversion["is_acquisition"]
    end

    test "conversion rows get channel from joined session" do
      session = create_session(channel: Channels::AFFILIATE)
      create_conversion(session: session)

      csv = export_and_parse
      conversion = csv.find { |row| row["type"] == FunnelStages::CONVERSION && row["channel"] == Channels::AFFILIATE }

      assert conversion, "expected conversion row with session channel"
    end

    # ==========================================
    # Row ordering
    # ==========================================

    test "rows ordered by date ascending" do
      create_session(started_at: 5.days.ago)
      create_event(occurred_at: 3.days.ago)
      create_conversion(converted_at: 1.day.ago)

      csv = export_and_parse
      dates = csv.map { |row| Date.parse(row["date"]) }

      assert_equal dates, dates.sort
    end

    # ==========================================
    # Filter tests
    # ==========================================

    test "respects date range filter" do
      Session.where(account: account).delete_all
      create_session(started_at: 5.days.ago)
      create_session(started_at: 35.days.ago)

      csv = export_and_parse(service(date_range: "7d"))
      visits = csv.select { |row| row["type"] == FunnelStages::VISIT }

      assert_equal 1, visits.size
    end

    test "respects channels filter" do
      Session.where(account: account).delete_all
      create_session(channel: Channels::PAID_SEARCH)
      create_session(channel: Channels::EMAIL)

      csv = export_and_parse(service(channels: [ Channels::PAID_SEARCH ]))
      visits = csv.select { |row| row["type"] == FunnelStages::VISIT }

      assert_equal 1, visits.size
      assert_equal Channels::PAID_SEARCH, visits.first["channel"]
    end

    test "respects funnel filter for events" do
      create_event(funnel: "sales")
      create_event(funnel: "marketing")

      csv = export_and_parse(service(funnel: "sales"))
      events = csv.select { |row| row["type"] == FunnelStages::EVENT }

      assert events.all? { |row| row["funnel"] == "sales" }
    end

    test "respects test mode" do
      Session.where(account: account).delete_all
      create_session(is_test: false)
      create_session(is_test: true)

      csv = export_and_parse(service(test_mode: true))
      visits = csv.select { |row| row["type"] == FunnelStages::VISIT }

      assert_equal 1, visits.size
    end

    # ==========================================
    # Nil value handling
    # ==========================================

    test "handles nil UTM, revenue, and properties" do
      Session.where(account: account).delete_all
      create_session(initial_utm: {})

      csv = export_and_parse
      row = csv.first

      assert_nil row["utm_source"]
      assert_nil row["utm_medium"]
      assert_nil row["utm_campaign"]
    end

    # ==========================================
    # Multi-account isolation
    # ==========================================

    test "cannot access other account's sessions" do
      Session.where(account: account).delete_all
      create_session
      other_account = accounts(:two)
      other_account.sessions.create!(
        visitor: visitors(:three),
        session_id: "sess_other_test_#{SecureRandom.hex(4)}",
        started_at: 1.hour.ago,
        channel: Channels::DIRECT
      )

      csv = export_and_parse

      assert csv.none? { |row| row["channel"] == Channels::DIRECT }
    end

    private

    def expected_headers
      %w[
        date type name funnel channel
        utm_source utm_medium utm_campaign
        revenue currency is_acquisition properties
      ]
    end

    def service(date_range: "30d", channels: Channels::ALL, funnel: nil, test_mode: false)
      filter_params = {
        date_range: date_range,
        channels: channels,
        funnel: funnel,
        test_mode: test_mode
      }
      Dashboard::FunnelCsvExportService.new(account, filter_params)
    end

    def account
      @account ||= accounts(:one)
    end

    def visitor
      @visitor ||= visitors(:one)
    end

    def default_session
      @default_session ||= sessions(:one)
    end

    def export_and_parse(svc = service)
      file = Tempfile.new([ "export_test", ".csv" ])
      svc.write_to(file.path)
      CSV.parse(File.read(file.path), headers: true)
    ensure
      file&.close!
    end

    def create_session(started_at: 1.hour.ago, channel: Channels::PAID_SEARCH, initial_utm: nil, is_test: false)
      account.sessions.create!(
        visitor: visitor,
        session_id: "sess_test_#{SecureRandom.hex(4)}",
        started_at: started_at,
        channel: channel,
        initial_utm: initial_utm || {},
        is_test: is_test
      )
    end

    def create_event(**attrs)
      defaults = { event_type: "page_view", occurred_at: 1.hour.ago, session: default_session,
                   funnel: nil, properties: { "url" => "https://example.com" } }
      attrs = defaults.merge(attrs)
      session = attrs.delete(:session)
      account.events.create!(visitor: visitor, session: session, **attrs)
    end

    def create_conversion(**attrs)
      defaults = { conversion_type: "purchase", converted_at: 1.hour.ago, session: default_session, currency: "USD" }
      attrs = defaults.merge(attrs)
      session = attrs.delete(:session)
      account.conversions.create!(
        visitor: visitor,
        session_id: session.id,
        **attrs
      )
    end
  end
end
