# frozen_string_literal: true

require "test_helper"

class Score::ReportServiceTest < ActiveSupport::TestCase
  setup do
    @assessment = ScoreAssessment.create!(
      overall_score: 1.8,
      overall_level: 1,
      dimension_scores: {
        "reporting" => 1.5, "attribution" => 1.0, "experimentation" => 1.0,
        "forecasting" => 1.5, "channels" => 2.0, "infrastructure" => 1.5
      },
      answers: [],
      context: { "ad_spend" => "100k-500k", "company_size" => "51-200", "role" => "marketing" }
    )
  end

  test "generates report with all sections" do
    report = Score::ReportService.new(@assessment).call

    assert_kind_of Hash, report[:dimensions]
    assert_kind_of Hash, report[:business_case]
    assert_kind_of Array, report[:roadmap]
  end

  test "dimensions include all six with analysis" do # rubocop:disable Minitest/MultipleAssertions
    report = Score::ReportService.new(@assessment).call

    Score::DIMENSIONS.each do |dim|
      assert report[:dimensions].key?(dim), "Missing dimension: #{dim}"

      analysis = report[:dimensions][dim]

      assert_predicate analysis[:score], :present?
      assert_predicate analysis[:level], :present?
      assert_predicate analysis[:label], :present?
      assert_predicate analysis[:what_this_means], :present?
      assert_predicate analysis[:next_level], :present?
    end
  end

  test "business case uses ad spend from context" do # rubocop:disable Minitest/MultipleAssertions
    report = Score::ReportService.new(@assessment).call

    assert_equal "100k-500k", report[:business_case][:ad_spend_bracket]
    assert_predicate report[:business_case][:estimated_waste_low], :positive?
    assert_predicate report[:business_case][:estimated_waste_high], :positive?
    assert_predicate report[:business_case][:cfo_slide], :present?
  end

  test "roadmap returns actions for next level" do # rubocop:disable Minitest/MultipleAssertions
    report = Score::ReportService.new(@assessment).call

    assert_operator report[:roadmap].length, :>=, 3

    report[:roadmap].each do |action|
      assert_predicate action[:title], :present?
      assert_predicate action[:why], :present?
      assert_predicate action[:effort], :present?
      assert_kind_of Array, action[:tools]
    end
  end

  test "roadmap is level-specific" do
    l3_assessment = ScoreAssessment.create!(
      overall_score: 3.0, overall_level: 3,
      dimension_scores: {}, answers: [], context: {}
    )

    l1_report = Score::ReportService.new(@assessment).call
    l3_report = Score::ReportService.new(l3_assessment).call

    refute_equal l1_report[:roadmap].first[:title], l3_report[:roadmap].first[:title]
  end
end
