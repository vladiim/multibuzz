# frozen_string_literal: true

require "test_helper"

class WaitlistHelperTest < ActionView::TestCase
  include WaitlistHelper

  # --- Logged In User Tests ---

  test "waitlist_button renders button_to for logged-in user" do
    stub_logged_in(true)

    html = waitlist_button(
      feature_key: "data_export",
      feature_name: "Data Export"
    )

    assert_match(/form/, html)
    assert_match(/feature_waitlist/, html)
    assert_match(/data_export/, html)
    assert_match(/Data Export/, html)
  end

  test "waitlist_button includes context param when provided" do
    stub_logged_in(true)

    html = waitlist_button(
      feature_key: "csv_export",
      feature_name: "CSV Export",
      context: "dashboard"
    )

    assert_match(/dashboard/, html)
  end

  test "waitlist_button uses default label" do
    stub_logged_in(true)

    html = waitlist_button(
      feature_key: "data_export",
      feature_name: "Data Export"
    )

    assert_match(/Join Waitlist/, html)
  end

  test "waitlist_button accepts custom label" do
    stub_logged_in(true)

    html = waitlist_button(
      feature_key: "data_export",
      feature_name: "Data Export",
      label: "Notify Me"
    )

    assert_match(/Notify Me/, html)
    assert_no_match(/Join Waitlist/, html)
  end

  test "waitlist_button accepts custom CSS classes" do
    stub_logged_in(true)

    html = waitlist_button(
      feature_key: "data_export",
      feature_name: "Data Export",
      class: "bg-blue-500 text-white"
    )

    assert_match(/bg-blue-500/, html)
    assert_match(/text-white/, html)
  end

  test "waitlist_button accepts block for custom content" do
    stub_logged_in(true)

    html = waitlist_button(
      feature_key: "data_export",
      feature_name: "Data Export"
    ) { "Custom Content" }

    assert_match(/Custom Content/, html)
  end

  # --- Logged Out User Tests ---

  test "waitlist_button renders modal trigger for logged-out user" do
    stub_logged_in(false)

    html = waitlist_button(
      feature_key: "data_export",
      feature_name: "Data Export"
    )

    assert_match(/button/, html)
    assert_match(/modal/, html)
    assert_match(/data_export/, html)
  end

  test "waitlist_button modal trigger has correct data attributes" do
    stub_logged_in(false)

    html = waitlist_button(
      feature_key: "pdf_export",
      feature_name: "PDF Export"
    )

    assert_match(/data-action/, html)
    assert_match(/pdf_export/, html)
  end

  # --- waitlist_modal partial ---

  test "waitlist_modal renders form with email input" do
    html = waitlist_modal(
      feature_key: "data_export",
      feature_name: "Data Export"
    )

    assert_match(/form/, html)
    assert_match(/email/, html)
    assert_match(/data_export/, html)
    assert_match(/Data Export/, html)
  end

  test "waitlist_modal includes hidden fields for feature data" do
    html = waitlist_modal(
      feature_key: "csv_export",
      feature_name: "CSV Export",
      context: "homepage"
    )

    assert_match(/hidden/, html)
    assert_match(/csv_export/, html)
    assert_match(/homepage/, html)
  end

  private

  def stub_logged_in(value)
    @logged_in = value
  end

  def logged_in?
    @logged_in
  end
end
