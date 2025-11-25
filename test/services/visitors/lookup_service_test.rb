require "test_helper"

class Visitors::LookupServiceTest < ActiveSupport::TestCase
  test "should find existing visitor" do
    assert result[:success]
    assert_equal visitor, result[:visitor]
    assert_not result[:created]
  end

  test "should create new visitor if not found" do
    @existing_visitor_id = "vis_new_visitor_123"

    assert_difference -> { Visitor.count }, 1 do
      assert result[:success]
      assert result[:created]
      assert_equal "vis_new_visitor_123", result[:visitor].visitor_id
      assert_equal account, result[:visitor].account
    end
  end

  test "should update last_seen_at for existing visitor" do
    old_time = 1.day.ago
    visitor.update_column(:last_seen_at, old_time)

    # Create fresh service instance to avoid memoization
    fresh_result = Visitors::LookupService.new(account, existing_visitor_id).call

    assert_in_delta Time.current, fresh_result[:visitor].last_seen_at, 1.second
  end

  test "should scope visitor to account" do
    assert_equal account, result[:visitor].account
  end

  test "should handle validation errors" do
    @existing_visitor_id = "a"  # Too short

    assert_not result[:success]
    assert result[:errors].present?
  end

  private

  def result
    @result ||= service.call
  end

  def service
    @service ||= Visitors::LookupService.new(account, existing_visitor_id)
  end

  def account
    @account ||= accounts(:one)
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def existing_visitor_id
    @existing_visitor_id ||= visitor.visitor_id
  end
end
