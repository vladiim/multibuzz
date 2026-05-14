# frozen_string_literal: true

require "test_helper"

module ConversionDispatches
  class AdminFilterQueryTest < ActiveSupport::TestCase
    test "no filters returns all dispatches ordered most-recent-first" do
      older = make_dispatch(created_at: 2.days.ago)
      newer = make_dispatch(created_at: 1.hour.ago)

      assert_equal [ newer.id, older.id ], AdminFilterQuery.new({}).call.map(&:id)
    end

    test "status filter narrows to matching status" do
      delivered = make_dispatch(status: ConversionDispatch::Statuses::DELIVERED, fired_at: 1.minute.ago)
      make_dispatch(status: ConversionDispatch::Statuses::FAILED_PERMANENT)

      result = AdminFilterQuery.new(status: ConversionDispatch::Statuses::DELIVERED).call

      assert_equal [ delivered.id ], result.map(&:id)
    end

    test "account filter resolves prefix_id and narrows" do
      mine = make_dispatch(account: account)
      make_dispatch(account: other_account, destination: other_destination)

      result = AdminFilterQuery.new(account_id: account.prefix_id).call

      assert_equal [ mine.id ], result.map(&:id)
    end

    test "unknown account prefix_id returns no results" do
      make_dispatch

      assert_empty AdminFilterQuery.new(account_id: "acct_nonexistent").call
    end

    test "destination filter narrows by destination id" do
      kept = make_dispatch
      make_dispatch(destination: other_destination)

      result = AdminFilterQuery.new(conversion_destination_id: destination.id).call

      assert_equal [ kept.id ], result.map(&:id)
    end

    test "date range filter narrows by created_at" do
      make_dispatch(created_at: 10.days.ago)
      kept = make_dispatch(created_at: 1.day.ago)

      result = AdminFilterQuery.new(from: 3.days.ago.to_date.to_s, to: Date.current.to_s).call

      assert_equal [ kept.id ], result.map(&:id)
    end

    test "malformed date in from/to is ignored" do
      kept = make_dispatch

      result = AdminFilterQuery.new(from: "not-a-date", to: "nope").call

      assert_includes result.map(&:id), kept.id
    end

    private

    def account = @account ||= accounts(:one)
    def other_account = @other_account ||= accounts(:two)

    def destination
      @destination ||= ConversionDestination.create!(
        account: account, attribution_model: attribution_models(:last_touch),
        platform: "meta_capi", name: "Primary",
        meta_pixel_id: "P1", meta_access_token: "T1", enabled: true
      )
    end

    def other_destination
      @other_destination ||= ConversionDestination.create!(
        account: other_account, attribution_model: attribution_models(:last_touch),
        platform: "meta_capi", name: "Other",
        meta_pixel_id: "P2", meta_access_token: "T2", enabled: true
      )
    end

    DEFAULT_DISPATCH = {
      status: ConversionDispatch::Statuses::DELIVERED,
      fired_at: nil,
      created_at: nil,
      account: nil,
      destination: nil
    }.freeze

    def make_dispatch(**overrides)
      opts = DEFAULT_DISPATCH.merge(overrides)
      acct = opts[:account] || account
      dest = opts[:destination] || (acct == account ? destination : other_destination)
      conv = acct.conversions.create!(
        visitor: acct == account ? visitors(:one) : visitors(:two),
        conversion_type: "Lead", converted_at: Time.current,
        idempotency_key: "afq_#{SecureRandom.hex(4)}"
      )
      dispatch = ConversionDispatch.create!(
        conversion: conv, conversion_destination: dest, account: acct,
        status: opts[:status], fired_at: opts[:fired_at] || dispatch_fired_at_for(opts[:status])
      )
      dispatch.update!(created_at: opts[:created_at]) if opts[:created_at]
      dispatch
    end

    def dispatch_fired_at_for(status)
      status == ConversionDispatch::Statuses::DELIVERED ? 1.minute.ago : nil
    end
  end
end
