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

  test "data-downloads page has a quickstart with curl + sample JSON envelope" do
    get docs_path(page: "data-downloads")

    body = response.body

    assert_match(/Quickstart/i, body)
    assert_match(/MBUZZ_API_KEY/, body)
    assert_match(/total_pages/, body)
  end

  test "data-downloads page documents test vs live keys" do
    get docs_path(page: "data-downloads")

    body = response.body

    assert_match(/sk_test/, body)
    assert_match(/sk_live/, body)
  end

  test "data-downloads page documents versioning and rate limits" do
    get docs_path(page: "data-downloads")

    body = response.body

    assert_match(/Versioning/i, body)
    assert_match(/Rate limits/i, body)
  end

  test "data-downloads page includes a pagination loop recipe" do
    get docs_path(page: "data-downloads")

    body = response.body

    assert_match(/Pagination/i, body)
    assert_match(/total_pages/, body)
    assert_match(/per_page=1000/, body)
  end

  test "data-downloads page links from API keys page" do
    sign_in_as users(:one)
    get account_api_keys_path

    assert_select "a[href=?]", docs_path(page: "data-downloads")
  end

  test "authentication next steps links to data-downloads" do
    get docs_path(page: "authentication")

    assert_select "a[href=?]", docs_path(page: "data-downloads")
  end

  test "getting-started next steps links to data-downloads" do
    get docs_path(page: "getting-started")

    assert_select "a[href=?]", docs_path(page: "data-downloads")
  end
end
