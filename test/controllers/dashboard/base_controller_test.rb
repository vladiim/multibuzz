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

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end
end
