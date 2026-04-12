# frozen_string_literal: true

require "test_helper"

class ApplicationServiceTest < ActiveSupport::TestCase
  # --- Our integration: services report errors via Rails.error ---

  test "reports errors via Rails.error with service class in context" do
    reported = capture_error_report { FailingService.new.call }

    assert reported, "Service should report error via Rails.error"
    assert_includes reported[:context][:service], "FailingService"
  end

  test "includes account_id in context when @account is set" do
    reported = capture_error_report { FailingServiceWithAccount.new(account).call }

    assert_equal account.id, reported[:context][:account_id]
  end

  # --- Behavior unchanged ---

  test "still returns error_result hash on failure" do
    result = FailingService.new.call

    refute result[:success]
    assert_includes result[:errors].first, "Something went wrong"
  end

  test "still returns success_result on success" do
    result = SucceedingService.new.call

    assert result[:success]
  end

  private

  def account
    @account ||= accounts(:one)
  end

  def capture_error_report(&block)
    reported = nil
    subscriber = TestErrorSubscriber.new { |e, ctx| reported = { error: e, context: ctx } }
    Rails.error.subscribe(subscriber)
    block.call
    Rails.error.unsubscribe(subscriber)
    reported
  end

  class TestErrorSubscriber
    def initialize(&block) = @block = block
    def report(error, handled:, severity:, context:, source: nil) = @block.call(error, context)
  end

  class FailingService < ApplicationService
    private
    def run = raise StandardError, "something broke"
  end

  class FailingServiceWithAccount < ApplicationService
    def initialize(account) = @account = account
    private
    attr_reader :account
    def run = raise StandardError, "something broke"
  end

  class SucceedingService < ApplicationService
    private
    def run = success_result(data: "ok")
  end
end
