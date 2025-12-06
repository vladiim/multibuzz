require "test_helper"

class Dashboard::BaseControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "models param uses account's default attribution model when not specified" do
    get dashboard_filters_path

    assert_response :success
    assert_equal [attribution_models(:first_touch)], controller.send(:selected_attribution_models)
  end

  test "models param rejects attribution model from different account" do
    other_account_model = attribution_models(:linear)

    get dashboard_filters_path(models: [other_account_model.prefix_id])

    assert_response :success
    assert_equal [attribution_models(:first_touch)], controller.send(:selected_attribution_models)
  end

  test "models param allows selecting up to 2 models" do
    first_touch = attribution_models(:first_touch)
    last_touch = attribution_models(:last_touch)

    get dashboard_filters_path(models: [first_touch.prefix_id, last_touch.prefix_id])

    assert_response :success
    assert_equal [first_touch, last_touch], controller.send(:selected_attribution_models)
  end

  test "channels param filters out invalid channels" do
    get dashboard_filters_path(channels: "paid_search,bogus,email")

    assert_response :success
    assert_equal %w[paid_search email], controller.send(:channels_param)
  end

  test "journey_position param defaults to last_touch" do
    get dashboard_filters_path

    assert_response :success
    assert_equal AttributionAlgorithms::DEFAULT_JOURNEY_POSITION, controller.send(:journey_position_param)
  end

  test "view_mode defaults to production" do
    get dashboard_filters_path

    assert_response :success
    assert_equal "production", controller.send(:view_mode)
    assert_not controller.send(:test_mode?)
  end

  test "view_mode returns test when set in session" do
    get dashboard_filters_path
    assert_response :success

    # Set test mode via the view_mode controller
    patch dashboard_view_mode_path(mode: "test")

    get dashboard_filters_path
    assert_response :success
    assert_equal "test", controller.send(:view_mode)
    assert controller.send(:test_mode?)
  end

  test "view_mode ignores invalid values" do
    get dashboard_filters_path
    assert_response :success

    # Try to set invalid mode
    patch dashboard_view_mode_path(mode: "invalid")

    get dashboard_filters_path
    assert_response :success
    assert_equal "production", controller.send(:view_mode)
  end

  test "environment_scope returns production scope by default" do
    get dashboard_filters_path

    assert_response :success
    assert_equal :production, controller.send(:environment_scope)
  end

  test "environment_scope returns test_data scope when in test mode" do
    patch dashboard_view_mode_path(mode: "test")
    get dashboard_filters_path

    assert_response :success
    assert_equal :test_data, controller.send(:environment_scope)
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end
end
