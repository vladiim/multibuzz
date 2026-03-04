# frozen_string_literal: true

require "test_helper"

class Dashboard::ConversionDetailControllerTest < ActionDispatch::IntegrationTest
  setup do
    accounts(:one).update!(live_mode_enabled: true)
    sign_in_as users(:one)
  end

  # --- Index (Conversions Table) ---

  test "index renders conversions table" do
    get dashboard_conversion_list_path

    assert_response :success
  end

  test "index only shows current accounts conversions" do
    get dashboard_conversion_list_path

    assert_response :success
    conversions = controller.instance_variable_get(:@conversions)

    assert conversions.all? { |c| c.account_id == account.id }
  end

  test "index paginates results" do
    30.times do |i|
      account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: i.days.ago
      )
    end

    get dashboard_conversion_list_path

    conversions = controller.instance_variable_get(:@conversions)

    assert_operator conversions.size, :<=, 25
  end

  test "index filters by conversion_type" do
    get dashboard_conversion_list_path, params: { conversion_type: "signup" }

    assert_response :success
    conversions = controller.instance_variable_get(:@conversions)

    assert conversions.all? { |c| c.conversion_type == "signup" }
  end

  test "index sorts by converted_at desc by default" do
    get dashboard_conversion_list_path

    conversions = controller.instance_variable_get(:@conversions)
    dates = conversions.map(&:converted_at)

    assert_equal dates, dates.sort.reverse
  end

  test "index requires login" do
    delete logout_path
    get dashboard_conversion_list_path

    assert_redirected_to login_path
  end

  # --- Show (Conversion Detail) ---

  test "show renders conversion detail" do
    get dashboard_conversion_detail_path(conversion.prefix_id)

    assert_response :success
  end

  test "show loads conversion with journey sessions" do
    s1 = create_test_session(started_at: 10.days.ago, channel: Channels::PAID_SEARCH)
    s2 = create_test_session(started_at: 5.days.ago, channel: Channels::EMAIL)
    conversion.update_column(:journey_session_ids, [ s1.id, s2.id ])

    get dashboard_conversion_detail_path(conversion.prefix_id)

    assert_response :success
    loaded = controller.instance_variable_get(:@conversion)

    assert_equal 2, loaded.journey_sessions.size
  end

  test "show returns 404 for other accounts conversion" do
    other_conversion = conversions(:trial_start)

    get dashboard_conversion_detail_path(other_conversion.prefix_id)

    assert_response :not_found
  end

  test "show returns 404 for nonexistent conversion" do
    get dashboard_conversion_detail_path("conv_nonexistent")

    assert_response :not_found
  end

  test "show requires login" do
    delete logout_path
    get dashboard_conversion_detail_path(conversion.prefix_id)

    assert_redirected_to login_path
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  def account = @account ||= accounts(:one)
  def conversion = @conversion ||= conversions(:purchase)

  def create_test_session(started_at:, channel:)
    account.sessions.create!(
      visitor: visitors(:one),
      session_id: "sess_#{SecureRandom.hex(8)}",
      started_at: started_at,
      channel: channel
    )
  end
end
