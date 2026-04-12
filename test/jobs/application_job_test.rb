# frozen_string_literal: true

require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  # --- Our integration: jobs retry on failure ---

  test "retries on StandardError" do
    assert_enqueued_with(job: FailingTestJob) do
      FailingTestJob.perform_later
    end
  end

  test "discards on DeserializationError" do
    assert ApplicationJob.rescue_handlers.any? { |h| h.first == "ActiveJob::DeserializationError" },
      "ApplicationJob should have a discard handler for DeserializationError"
  end

  test "discards on DatabaseConnectionError" do
    assert ApplicationJob.rescue_handlers.any? { |h| h.first == "ActiveRecord::DatabaseConnectionError" },
      "ApplicationJob should discard on DatabaseConnectionError"
  end

  test "discards on ConnectionNotEstablished" do
    assert ApplicationJob.rescue_handlers.any? { |h| h.first == "ActiveRecord::ConnectionNotEstablished" },
      "ApplicationJob should discard on ConnectionNotEstablished"
  end

  private

  class FailingTestJob < ApplicationJob
    def perform
      raise StandardError, "job failed"
    end
  end
end
