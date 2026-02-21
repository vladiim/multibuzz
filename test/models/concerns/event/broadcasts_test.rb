# frozen_string_literal: true

require "test_helper"

class Event::BroadcastsTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "broadcasts to account channel on create" do
    stream_name = "account_#{account.prefix_id}_events"

    assert_broadcasts(stream_name, 1) do
      create_event
    end
  end

  test "does not broadcast on update" do
    event = create_event
    clear_enqueued_jobs if respond_to?(:clear_enqueued_jobs)

    stream_name = "account_#{account.prefix_id}_events"

    assert_no_broadcasts(stream_name) do
      event.update!(properties: { url: "https://updated.com" })
    end
  end

  test "broadcast targets events-list" do
    stream_name = "account_#{account.prefix_id}_events"

    create_event

    broadcast = broadcasts(stream_name).last

    assert_includes broadcast, "events-list"
  end

  private

  def account
    @account ||= accounts(:one)
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def session
    @session ||= account.sessions.create!(
      session_id: "test_session_#{SecureRandom.hex(4)}",
      visitor: visitor,
      started_at: Time.current,
      channel: Channels::DIRECT
    )
  end

  def create_event
    account.events.create!(
      visitor: visitor,
      session: session,
      event_type: "page_view",
      occurred_at: Time.current,
      properties: { url: "https://example.com" }
    )
  end
end
