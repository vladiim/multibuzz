# frozen_string_literal: true

require "test_helper"

class Dashboard::LiveEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:one)
    @user = users(:one)
    # Clear existing events to isolate tests
    Event.delete_all
    sign_in_as(@user)
  end

  # ==========================================
  # Basic access tests
  # ==========================================

  test "requires authentication" do
    delete logout_path
    get dashboard_live_path

    assert_redirected_to login_path
  end

  test "renders successfully" do
    get dashboard_live_path

    assert_response :success
  end

  # ==========================================
  # Event loading tests
  # ==========================================

  test "loads recent events for account" do
    create_test_event(event_type: "page_view")

    get dashboard_live_path

    assert_response :success
    assert_select "[data-event-id]", count: 1
  end

  test "orders events by occurred_at descending" do
    old_event = create_test_event(event_type: "page_view", occurred_at: 2.hours.ago)
    new_event = create_test_event(event_type: "purchase", occurred_at: 1.hour.ago)

    get dashboard_live_path

    assert_response :success
    # New event should appear before old event
    event_ids = css_select("[data-event-id]").map { |el| el["data-event-id"] }
    assert_equal [new_event.prefix_id, old_event.prefix_id], event_ids
  end

  test "limits to 100 events" do
    105.times { |i| create_test_event(event_type: "page_view", occurred_at: i.minutes.ago) }

    get dashboard_live_path

    assert_response :success
    assert_select "[data-event-id]", count: 100
  end

  # ==========================================
  # Filter tests
  # ==========================================

  test "shows all events by default" do
    create_test_event(event_type: "page_view", is_test: false)
    create_test_event(event_type: "purchase", is_test: true)

    get dashboard_live_path

    assert_response :success
    assert_select "[data-event-id]", count: 2
  end

  test "filters to test events only when test_only param is true" do
    create_test_event(event_type: "page_view", is_test: false)
    create_test_event(event_type: "purchase", is_test: true)

    get dashboard_live_path(test_only: "true")

    assert_response :success
    assert_select "[data-event-id]", count: 1
  end

  # ==========================================
  # Multi-tenancy tests
  # ==========================================

  test "only shows events for current account" do
    create_test_event(event_type: "page_view")

    # Create event for different account
    other_account = accounts(:two)
    other_visitor = visitors(:three)
    other_session = other_account.sessions.create!(
      session_id: "other_session",
      visitor: other_visitor,
      started_at: Time.current,
      channel: Channels::DIRECT
    )
    other_account.events.create!(
      visitor: other_visitor,
      session: other_session,
      event_type: "page_view",
      occurred_at: Time.current,
      properties: { url: "https://other.com" }
    )

    get dashboard_live_path

    assert_response :success
    assert_select "[data-event-id]", count: 1
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  def create_test_event(event_type:, occurred_at: Time.current, is_test: false)
    session = @account.sessions.create!(
      session_id: "session_#{SecureRandom.hex(4)}",
      visitor: visitors(:one),
      started_at: occurred_at,
      channel: Channels::PAID_SEARCH,
      is_test: is_test
    )

    @account.events.create!(
      visitor: visitors(:one),
      session: session,
      event_type: event_type,
      occurred_at: occurred_at,
      is_test: is_test,
      properties: { url: "https://example.com/#{event_type}" }
    )
  end
end
