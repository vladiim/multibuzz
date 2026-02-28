# frozen_string_literal: true

require "test_helper"

class AdSpendRecordTest < ActiveSupport::TestCase
  # --- Relationships ---

  test "belongs to account" do
    assert_equal accounts(:one), record.account
  end

  test "belongs to ad_platform_connection" do
    assert_equal ad_platform_connections(:google_ads), record.ad_platform_connection
  end

  # --- Validations ---

  test "requires spend_date" do
    record.spend_date = nil

    assert_not record.valid?
  end

  test "requires channel" do
    record.channel = nil

    assert_not record.valid?
  end

  test "requires channel from valid list" do
    record.channel = "invalid_channel"

    assert_not record.valid?
    assert_includes record.errors[:channel], "is not included in the list"
  end

  test "requires platform_campaign_id" do
    record.platform_campaign_id = nil

    assert_not record.valid?
  end

  test "requires campaign_name" do
    record.campaign_name = nil

    assert_not record.valid?
  end

  test "requires currency" do
    record.currency = nil

    assert_not record.valid?
  end

  test "spend_micros must be non-negative" do
    record.spend_micros = -1

    assert_not record.valid?
  end

  test "impressions must be non-negative" do
    record.impressions = -1

    assert_not record.valid?
  end

  test "clicks must be non-negative" do
    record.clicks = -1

    assert_not record.valid?
  end

  # --- Spend Conversion ---

  test "spend converts micros to decimal" do
    record.spend_micros = 12_400_000

    assert_in_delta(12.4, record.spend)
  end

  test "spend returns zero for zero micros" do
    record.spend_micros = 0

    assert_equal 0, record.spend
  end

  test "platform_conversion_value converts micros to decimal" do
    record.platform_conversion_value_micros = 50_000_000

    assert_in_delta(50.0, record.platform_conversion_value)
  end

  # --- Scopes ---

  test "production scope excludes test records" do
    results = account.ad_spend_records.production

    assert results.none?(&:is_test)
  end

  test "test_data scope returns only test records" do
    results = account.ad_spend_records.test_data

    assert results.all?(&:is_test)
  end

  test "for_date_range filters by spend_date" do
    results = account.ad_spend_records.for_date_range(Date.current..Date.current)

    assert results.all? { |r| r.spend_date == Date.current }
  end

  test "for_channel filters by channel" do
    results = account.ad_spend_records.for_channel("display")

    assert results.all? { |r| r.channel == "display" }
  end

  # --- Prefix ID ---

  test "has aspend prefix id" do
    assert record.prefix_id.start_with?("aspend_")
  end

  # --- Multi-tenancy ---

  test "account one cannot access account two records" do
    account_one_records = accounts(:one).ad_spend_records
    other = ad_spend_records(:other_account_record)

    assert_not_includes account_one_records, other
  end

  private

  def record = @record ||= ad_spend_records(:paid_search_today)
  def account = @account ||= accounts(:one)
end
