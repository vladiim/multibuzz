# frozen_string_literal: true

require "test_helper"

module AML
  class TemplatesTest < ActiveSupport::TestCase
    # Template definitions
    test "defines 6 default templates" do
      assert_equal 6, AML::Templates::DEFINITIONS.length
    end

    test "includes all expected algorithms" do
      expected = %i[first_touch last_touch linear time_decay u_shaped participation]
      assert_equal expected.sort, AML::Templates::DEFINITIONS.keys.sort
    end

    test "each template has required attributes" do
      AML::Templates::DEFINITIONS.each do |key, template|
        assert template[:name].present?, "#{key} missing name"
        assert template[:description].present?, "#{key} missing description"
        assert template[:code].present?, "#{key} missing code"
      end
    end

    # Generation
    test "generate returns code with lookback_days interpolated" do
      code = AML::Templates.generate(:first_touch, lookback_days: 60)

      assert_includes code, "60.days"
      assert_includes code, "within_window"
    end

    test "generate uses default lookback_days of 30" do
      code = AML::Templates.generate(:first_touch)

      assert_includes code, "30.days"
    end

    test "generate raises for unknown algorithm" do
      assert_raises(KeyError) do
        AML::Templates.generate(:unknown_algorithm)
      end
    end

    # All templates
    test "all returns list of template hashes" do
      templates = AML::Templates.all

      assert_equal 6, templates.length
      assert templates.all? { |t| t[:key].present? }
      assert templates.all? { |t| t[:name].present? }
    end

    # Find
    test "find returns template by key" do
      template = AML::Templates.find(:first_touch)

      assert_equal "First Touch", template[:name]
    end

    test "find returns nil for unknown key" do
      assert_nil AML::Templates.find(:unknown)
    end

    # Security validation - all templates pass
    test "first_touch template passes security validation" do
      assert_template_secure(:first_touch)
    end

    test "last_touch template passes security validation" do
      assert_template_secure(:last_touch)
    end

    test "linear template passes security validation" do
      assert_template_secure(:linear)
    end

    test "time_decay template passes security validation" do
      assert_template_secure(:time_decay)
    end

    test "u_shaped template passes security validation" do
      assert_template_secure(:u_shaped)
    end

    test "participation template passes security validation" do
      assert_template_secure(:participation)
    end

    # Execution - all templates execute successfully
    test "first_touch template executes and returns valid credits" do
      assert_template_executes(:first_touch)
    end

    test "last_touch template executes and returns valid credits" do
      assert_template_executes(:last_touch)
    end

    test "linear template executes and returns valid credits" do
      assert_template_executes(:linear)
    end

    test "time_decay template executes and returns valid credits" do
      assert_template_executes(:time_decay)
    end

    test "u_shaped template executes and returns valid credits" do
      assert_template_executes(:u_shaped)
    end

    test "participation template executes and returns valid credits" do
      assert_template_executes(:participation)
    end

    # Credit distribution correctness
    test "first_touch gives 100% to first touchpoint" do
      credits = execute_template(:first_touch)

      assert_equal 1.0, credits[0]
      assert_equal 0.0, credits[1]
      assert_equal 0.0, credits[2]
      assert_equal 0.0, credits[3]
    end

    test "last_touch gives 100% to last touchpoint" do
      credits = execute_template(:last_touch)

      assert_equal 0.0, credits[0]
      assert_equal 0.0, credits[1]
      assert_equal 0.0, credits[2]
      assert_equal 1.0, credits[3]
    end

    test "linear distributes equally" do
      credits = execute_template(:linear)

      credits.each do |credit|
        assert_in_delta 0.25, credit, 0.0001
      end
    end

    test "time_decay weights recent touchpoints higher" do
      credits = execute_template(:time_decay)

      assert credits[3] > credits[0], "Last should have more credit than first"
      assert_in_delta 1.0, credits.sum, 0.0001
    end

    test "u_shaped gives 40% first, 40% last, 20% middle" do
      credits = execute_template(:u_shaped)

      assert_in_delta 0.4, credits[0], 0.0001
      assert_in_delta 0.1, credits[1], 0.0001
      assert_in_delta 0.1, credits[2], 0.0001
      assert_in_delta 0.4, credits[3], 0.0001
    end

    # Edge cases
    test "templates work with single touchpoint" do
      %i[first_touch last_touch linear time_decay u_shaped].each do |algorithm|
        credits = execute_template(algorithm, touchpoint_count: 1)
        assert_in_delta 1.0, credits.sum, 0.0001, "#{algorithm} failed with single touchpoint"
      end
    end

    test "templates work with two touchpoints" do
      %i[first_touch last_touch linear time_decay u_shaped].each do |algorithm|
        credits = execute_template(algorithm, touchpoint_count: 2)
        assert_in_delta 1.0, credits.sum, 0.0001, "#{algorithm} failed with two touchpoints"
      end
    end

    private

    def assert_template_secure(algorithm)
      code = AML::Templates.generate(algorithm)
      analyzer = AML::Security::ASTAnalyzer.new(code)

      assert analyzer.valid?, "#{algorithm} template failed security validation"
    end

    def assert_template_executes(algorithm)
      credits = execute_template(algorithm)

      assert_equal 4, credits.length
      assert_in_delta 1.0, credits.sum, 0.0001
    end

    def execute_template(algorithm, touchpoint_count: 4)
      code = AML::Templates.generate(algorithm)

      AML::Executor.new(
        dsl_code: code,
        touchpoints: build_touchpoints(touchpoint_count),
        conversion_time: Time.current,
        conversion_value: 100.0
      ).call
    end

    def build_touchpoints(count)
      (0...count).map do |i|
        {
          session_id: i + 1,
          channel: "channel_#{i}",
          occurred_at: (count - i).days.ago
        }
      end
    end
  end
end
