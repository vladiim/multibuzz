# frozen_string_literal: true

require "test_helper"

class AttributionModels::TestServiceTest < ActiveSupport::TestCase
  # No database writes - all in-memory execution

  test "executes first touch model with four touchpoints" do
    result = service(first_touch_code, :four_touch).call

    assert result[:success]
    assert_equal 4, result[:results].length
    assert_in_delta(1.0, result[:results].first[:credit])
    assert_in_delta(0.0, result[:results].last[:credit])
    assert_in_delta 1.0, result[:total], 0.0001
  end

  test "executes last touch model with four touchpoints" do
    result = service(last_touch_code, :four_touch).call

    assert result[:success]
    assert_in_delta(0.0, result[:results].first[:credit])
    assert_in_delta(1.0, result[:results].last[:credit])
  end

  test "executes linear model with four touchpoints" do
    result = service(linear_code, :four_touch).call

    assert result[:success]
    result[:results].each do |r|
      assert_in_delta 0.25, r[:credit], 0.0001
      assert_in_delta 25.0, r[:percentage], 0.1
    end
  end

  test "executes u-shaped model with four touchpoints" do
    result = service(u_shaped_code, :four_touch).call

    assert result[:success]
    assert_in_delta 0.4, result[:results].first[:credit], 0.0001
    assert_in_delta 0.4, result[:results].last[:credit], 0.0001
    assert_in_delta 0.1, result[:results][1][:credit], 0.0001
    assert_in_delta 0.1, result[:results][2][:credit], 0.0001
  end

  test "handles two touch journey" do
    result = service(linear_code, :two_touch).call

    assert result[:success]
    assert_equal 2, result[:results].length
    assert_in_delta 0.5, result[:results].first[:credit], 0.0001
  end

  test "handles single touch journey" do
    result = service(first_touch_code, :single_touch).call

    assert result[:success]
    assert_equal 1, result[:results].length
    assert_in_delta(1.0, result[:results].first[:credit])
  end

  test "returns channel labels" do
    result = service(linear_code, :four_touch).call

    assert_equal "Organic Search", result[:results][0][:channel_label]
    assert_equal "Email", result[:results][1][:channel_label]
    assert_equal "Paid Search", result[:results][2][:channel_label]
    assert_equal "Direct", result[:results][3][:channel_label]
  end

  test "returns percentage values" do
    result = service(first_touch_code, :four_touch).call

    assert_in_delta(100.0, result[:results].first[:percentage])
    assert_in_delta(0.0, result[:results].last[:percentage])
  end

  test "returns error for invalid syntax" do
    result = service("this is not valid ruby {{{", :four_touch).call

    assert_not result[:success]
    assert_predicate result[:error], :present?
  end

  test "returns error for security violation" do
    result = service("system('ls')", :four_touch).call

    assert_not result[:success]
    assert_match(/not allowed|forbidden/i, result[:error])
  end

  test "returns error for missing within_window" do
    code = "apply 1.0, to: touchpoints.first"
    result = service(code, :four_touch).call

    assert_not result[:success]
    assert_match(/within_window/i, result[:error])
  end

  test "defaults to four_touch journey when invalid type provided" do
    result = service(linear_code, :invalid_journey).call

    assert result[:success]
    assert_equal 4, result[:results].length
  end

  private

  def service(code, journey_type)
    AttributionModels::TestService.new(dsl_code: code, journey_type: journey_type)
  end

  def first_touch_code
    <<~AML
      within_window 30.days do
        apply 1.0, to: touchpoints.first
      end
    AML
  end

  def last_touch_code
    <<~AML
      within_window 30.days do
        apply 1.0, to: touchpoints.last
      end
    AML
  end

  def linear_code
    <<~AML
      within_window 30.days do
        apply 1.0, to: touchpoints, distribute: :equal
      end
    AML
  end

  def u_shaped_code
    <<~AML
      within_window 30.days do
        apply 0.4, to: touchpoints.first
        apply 0.4, to: touchpoints.last
        apply 0.2, to: touchpoints[1..-2], distribute: :equal
      end
    AML
  end
end
