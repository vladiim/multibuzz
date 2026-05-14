# frozen_string_literal: true

require "test_helper"

class ConversionDispatchTest < ActiveSupport::TestCase
  test "has prefixed_id with cdisp_ prefix" do
    dispatch.save!

    assert_match(/\Acdisp_/, dispatch.prefix_id)
  end

  test "belongs to conversion destination account and optional attribution_model" do
    assert_equal destination, dispatch.conversion_destination
    assert_equal conversion, dispatch.conversion
    assert_equal account, dispatch.account
  end

  test "rejects blank status" do
    dispatch.status = nil

    assert_not dispatch.valid?
  end

  test "rejects unknown status" do
    dispatch.status = "made_up"

    assert_not dispatch.valid?
    assert_includes dispatch.errors[:status], "is not included in the list"
  end

  test "accepts canonical statuses" do
    ConversionDispatch::Statuses::ALL.each do |status|
      dispatch.status = status

      assert_predicate dispatch, :valid?, "#{status} should be valid"
    end
  end

  test "delivered? predicate" do
    dispatch.status = ConversionDispatch::Statuses::DELIVERED

    assert_predicate dispatch, :delivered?
    refute_predicate dispatch, :pending?
  end

  test "skipped? predicate covers any skipped_* status" do
    %w[skipped_no_identity skipped_no_credit skipped_account_suspended].each do |status|
      dispatch.status = status

      assert_predicate dispatch, :skipped?, "#{status} should report skipped?"
    end
  end

  test "failed? predicate covers any failed_* status plus token_failed" do
    %w[failed_transient failed_permanent token_failed].each do |status|
      dispatch.status = status

      assert_predicate dispatch, :failed?, "#{status} should report failed?"
    end
  end

  test "uniqueness on (conversion_id, conversion_destination_id)" do
    dispatch.save!
    duplicate = ConversionDispatch.new(
      conversion: conversion,
      conversion_destination: destination,
      account: account,
      status: ConversionDispatch::Statuses::PENDING
    )

    refute_predicate duplicate, :valid?
    assert_includes duplicate.errors[:conversion_id], "has already been taken"
  end

  private

  def dispatch
    @dispatch ||= ConversionDispatch.new(
      conversion: conversion,
      conversion_destination: destination,
      account: account,
      status: ConversionDispatch::Statuses::PENDING
    )
  end

  def conversion
    @conversion ||= conversions(:signup)
  end

  def destination
    @destination ||= ConversionDestination.create!(
      account: account,
      attribution_model: attribution_models(:last_touch),
      platform: "meta_capi",
      name: "BSA Meta CAPI",
      enabled: true
    )
  end

  def account
    @account ||= accounts(:one)
  end
end
