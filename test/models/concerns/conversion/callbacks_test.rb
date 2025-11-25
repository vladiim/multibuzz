# frozen_string_literal: true

require "test_helper"

class Conversion::CallbacksTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "queues attribution calculation job after create" do
    assert_enqueued_with(job: Conversions::AttributionCalculationJob) do
      Conversion.create!(
        account: account,
        visitor: visitor,
        session_id: 1,
        event_id: 1,
        conversion_type: "purchase",
        converted_at: Time.current,
        journey_session_ids: []
      )
    end
  end

  private

  def account
    @account ||= accounts(:one)
  end

  def visitor
    @visitor ||= visitors(:one)
  end
end
