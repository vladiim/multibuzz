# frozen_string_literal: true

require "test_helper"

class DemoControllerTest < ActionDispatch::IntegrationTest
  test "/demo redirects to /demo/dashboard" do
    get "/demo"

    assert_redirected_to "/demo/dashboard"
  end
end
