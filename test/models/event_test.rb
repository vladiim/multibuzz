require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "valid event" do
    assert event.valid?
  end

  test "requires event_type" do
    event.event_type = nil
    assert_not event.valid?
    assert_includes event.errors[:event_type], "can't be blank"
  end

  test "requires occurred_at" do
    event.occurred_at = nil
    assert_not event.valid?
    assert_includes event.errors[:occurred_at], "can't be blank"
  end

  test "requires properties" do
    event.properties = nil
    assert_not event.valid?
    assert_includes event.errors[:properties], "can't be blank"
  end

  test "properties must be a hash" do
    event.properties = "not a hash"
    assert_not event.valid?
    assert_includes event.errors[:properties], "must be a hash"
  end

  test "belongs to account" do
    assert_equal account, event.account
  end

  test "belongs to visitor" do
    assert_equal visitor, event.visitor
  end

  test "belongs to session" do
    assert_equal session, event.session
  end

  test "by_type scope filters by event type" do
    page_view_events = Event.by_type("page_view")
    assert_includes page_view_events, event
  end

  test "recent scope orders by occurred_at desc" do
    recent_events = account.events.recent
    assert_equal events(:two), recent_events.first
    assert_equal events(:one), recent_events.second
  end

  test "between scope filters by time range" do
    start_time = 2.hours.ago
    end_time = 45.minutes.ago

    events_in_range = account.events.between(start_time, end_time)
    assert_includes events_in_range, events(:one)
    assert_not_includes events_in_range, events(:two)
  end

  test "with_utm_source scope filters by utm source" do
    google_events = Event.with_utm_source("google")
    assert_includes google_events, events(:one)
    assert_not_includes google_events, events(:two)
  end

  test "with_utm_medium scope filters by utm medium" do
    cpc_events = Event.with_utm_medium("cpc")
    assert_includes cpc_events, events(:one)
    assert_not_includes cpc_events, events(:two)
  end

  test "with_utm_campaign scope filters by utm campaign" do
    campaign_events = Event.with_utm_campaign("spring_sale")
    assert_includes campaign_events, events(:one)
    assert_not_includes campaign_events, events(:two)
  end

  test "utm_source accessor returns utm_source from properties" do
    assert_equal "google", event.utm_source
  end

  test "utm_medium accessor returns utm_medium from properties" do
    assert_equal "cpc", event.utm_medium
  end

  test "utm_campaign accessor returns utm_campaign from properties" do
    assert_equal "spring_sale", event.utm_campaign
  end

  test "utm_content accessor returns utm_content from properties" do
    assert_equal "ad_variant_a", event.utm_content
  end

  test "utm_term accessor returns utm_term from properties" do
    assert_equal "running shoes", event.utm_term
  end

  test "url accessor returns url from properties" do
    assert_equal "https://example.com/page", event.url
  end

  test "referrer accessor returns nil when not present" do
    assert_nil event.referrer
  end

  private

  def event
    @event ||= events(:one)
  end

  def account
    @account ||= accounts(:one)
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def session
    @session ||= sessions(:one)
  end
end
