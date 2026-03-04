# frozen_string_literal: true

require "test_helper"

class Dashboard::IdentitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    accounts(:one).update!(live_mode_enabled: true)
    sign_in_as users(:one)
  end

  test "show renders identity detail" do
    get dashboard_identity_detail_path(identity.prefix_id)

    assert_response :success
  end

  test "show loads identity" do
    get dashboard_identity_detail_path(identity.prefix_id)

    assert_response :success
    assert controller.instance_variable_get(:@identity)
  end

  test "show computes engagement score" do
    get dashboard_identity_detail_path(identity.prefix_id)

    score = controller.instance_variable_get(:@engagement_score)

    assert score.key?(:score)
    assert score.key?(:tier)
  end

  test "show returns 404 for other accounts identity" do
    other = identities(:other_account_identity)

    get dashboard_identity_detail_path(other.prefix_id)

    assert_response :not_found
  end

  test "show returns 404 for nonexistent identity" do
    get dashboard_identity_detail_path("idt_nonexistent")

    assert_response :not_found
  end

  test "show requires login" do
    delete logout_path
    get dashboard_identity_detail_path(identity.prefix_id)

    assert_redirected_to login_path
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  def account = @account ||= accounts(:one)
  def identity = @identity ||= identities(:one)
end
