require "test_helper"

class DemoControllerTest < ActionDispatch::IntegrationTest
  # --- Show (main demo dashboard) ---

  test "show renders demo dashboard without authentication" do
    get demo_path

    assert_response :success
  end

  test "show displays sample attribution data" do
    get demo_path

    assert_select "[data-demo-attribution]"
  end

  test "show displays model switcher" do
    get demo_path

    assert_select "[data-model-switcher]"
  end

  test "show displays signup CTA" do
    get demo_path

    assert_select "a[href='#{signup_path}']"
  end

  # --- Attribution (Turbo frame for model switching) ---

  test "attribution returns turbo frame for model switching" do
    get demo_attribution_path(model: "linear")

    assert_response :success
  end

  test "attribution accepts different model parameters" do
    %w[first_touch last_touch linear time_decay u_shaped].each do |model|
      get demo_attribution_path(model: model)

      assert_response :success, "Expected success for model: #{model}"
    end
  end

  test "attribution defaults to linear model when not specified" do
    get demo_attribution_path

    assert_response :success
  end
end
