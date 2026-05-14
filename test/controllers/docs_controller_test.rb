# frozen_string_literal: true

require "test_helper"

class DocsControllerTest < ActionDispatch::IntegrationTest
  test "show renders getting-started" do
    get docs_path(page: "getting-started")

    assert_response :success
  end

  test "show 404s on unknown page" do
    get docs_path(page: "not-a-real-page")

    assert_response :not_found
  end

  test "show renders data-downloads page" do
    get docs_path(page: "data-downloads")

    assert_response :success
  end

  test "data-downloads page describes the three endpoints" do
    get docs_path(page: "data-downloads")

    body = response.body

    assert_match %r{/api/v1/data/conversions}, body
    assert_match %r{/api/v1/data/funnel}, body
    assert_match %r{/api/v1/data/spend}, body
  end

  test "data-downloads page includes auth + curl examples" do
    get docs_path(page: "data-downloads")

    body = response.body

    assert_match(/Authorization:\s*Bearer/i, body)
    assert_match(/curl/, body)
  end

  test "data-downloads page links from docs nav" do
    get docs_path(page: "getting-started")

    assert_select "a[href=?]", docs_path(page: "data-downloads")
  end
end
