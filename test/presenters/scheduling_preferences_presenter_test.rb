# frozen_string_literal: true

require "test_helper"

class SchedulingPreferencesPresenterTest < ActiveSupport::TestCase
  test "from(nil) accepts a missing preferences hash" do
    presenter = SchedulingPreferencesPresenter.from(nil)

    assert_equal "", presenter.timezone
    assert_empty presenter.days
    assert_empty presenter.time_blocks
  end

  test "from(prefs) exposes a populated hash through accessors" do
    presenter = SchedulingPreferencesPresenter.from(
      "timezone" => "Sydney",
      "days" => [ "tue", "wed" ],
      "time_blocks" => [ "morning" ]
    )

    assert_equal "Sydney", presenter.timezone
    assert_equal [ "tue", "wed" ], presenter.days
    assert_equal [ "morning" ], presenter.time_blocks
  end

  test "day_selected? reflects membership" do
    presenter = SchedulingPreferencesPresenter.from("days" => [ "tue" ])

    assert presenter.day_selected?("tue")
    assert_not presenter.day_selected?("wed")
  end

  test "time_block_selected? reflects membership" do
    presenter = SchedulingPreferencesPresenter.from("time_blocks" => [ "morning" ])

    assert presenter.time_block_selected?("morning")
    assert_not presenter.time_block_selected?("afternoon")
  end

  test "any_days? and any_time_blocks? report presence when populated" do
    presenter = SchedulingPreferencesPresenter.from("days" => [ "tue" ], "time_blocks" => [ "morning" ])

    assert_predicate presenter, :any_days?
    assert_predicate presenter, :any_time_blocks?
  end

  test "any_days? and any_time_blocks? return false when empty" do
    presenter = SchedulingPreferencesPresenter.from(nil)

    assert_not presenter.any_days?
    assert_not presenter.any_time_blocks?
  end

  test "day_labels joins human-readable day names" do
    presenter = SchedulingPreferencesPresenter.from("days" => [ "tue", "wed" ])

    assert_equal "Tue, Wed", presenter.day_labels
  end

  test "time_block_labels joins human-readable time-block names" do
    presenter = SchedulingPreferencesPresenter.from("time_blocks" => [ "morning", "afternoon" ])

    assert_equal "Morning, Afternoon", presenter.time_block_labels
  end

  test "unknown keys round-trip back without crashing" do
    presenter = SchedulingPreferencesPresenter.from("days" => [ "funday" ])

    assert_equal "Funday", presenter.day_labels
  end

  test "time_block_labels_with_hours appends the human time range" do
    presenter = SchedulingPreferencesPresenter.from("time_blocks" => [ "midday", "morning" ])

    assert_equal "Midday (12pm-3pm), Morning (6am-12pm)", presenter.time_block_labels_with_hours
  end

  test "time_block_labels_with_hours falls back gracefully for unknown blocks" do
    presenter = SchedulingPreferencesPresenter.from("time_blocks" => [ "midnight" ])

    assert_equal "Midnight", presenter.time_block_labels_with_hours
  end
end
