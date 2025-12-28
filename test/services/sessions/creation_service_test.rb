# frozen_string_literal: true

require "test_helper"

class Sessions::CreationServiceTest < ActiveSupport::TestCase
  # --- Billing Usage ---

  test "should increment usage counter when new session is created with existing visitor" do
    @params = {
      visitor_id: visitor.visitor_id,
      session_id: "sess_new_session_existing_visitor",
      url: "https://example.com/page"
    }

    assert_difference -> { usage_counter.current_usage }, 1 do
      result
    end
  end

  test "should increment usage counter for both visitor and session when both are new" do
    @params = {
      visitor_id: "vis_brand_new_visitor",
      session_id: "sess_brand_new_session",
      url: "https://example.com/page"
    }

    assert_difference -> { usage_counter.current_usage }, 2 do
      result
    end
  end

  test "should not increment usage counter when session already exists" do
    # Create the session first
    service.call

    # Second call with same session should not increment
    assert_no_difference -> { usage_counter.current_usage } do
      Sessions::CreationService.new(account, params).call
    end
  end

  private

  def result
    @result ||= service.call
  end

  def service
    @service ||= Sessions::CreationService.new(account, params)
  end

  def params
    @params ||= {
      visitor_id: "vis_new_visitor_123",
      session_id: "sess_new_session_123",
      url: "https://example.com/page"
    }
  end

  def account
    @account ||= accounts(:one)
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def usage_counter
    @usage_counter ||= Billing::UsageCounter.new(account)
  end
end
