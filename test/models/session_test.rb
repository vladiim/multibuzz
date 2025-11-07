require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "should be valid with valid attributes" do
    assert session.valid?
  end

  test "should belong to account" do
    assert_equal account, session.account
  end

  test "should belong to visitor" do
    assert_equal visitor, session.visitor
  end

  test "should require account" do
    session.account = nil

    assert_not session.valid?
    assert_includes session.errors[:account], "must exist"
  end

  test "should require visitor" do
    session.visitor = nil

    assert_not session.valid?
    assert_includes session.errors[:visitor], "must exist"
  end

  test "should require session_id" do
    session.session_id = nil

    assert_not session.valid?
    assert_includes session.errors[:session_id], "can't be blank"
  end

  test "should require unique session_id per account" do
    duplicate = Session.new(
      account: account,
      visitor: visitor,
      session_id: session.session_id
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:session_id], "has already been taken"
  end

  test "should allow same session_id across different accounts" do
    other_session = Session.new(
      account: other_account,
      visitor: other_visitor,
      session_id: session.session_id
    )

    assert other_session.valid?
  end

  test "should have many events" do
    assert_respond_to session, :events
  end

  test "should store initial_utm as jsonb" do
    session.update!(
      initial_utm: {
        utm_source: "google",
        utm_medium: "cpc",
        utm_campaign: "spring_sale"
      }
    )
    session.reload

    assert_equal "google", session.initial_utm["utm_source"]
    assert_equal "cpc", session.initial_utm["utm_medium"]
    assert_equal "spring_sale", session.initial_utm["utm_campaign"]
  end

  test "should track started_at on creation" do
    new_session = Session.create!(
      account: account,
      visitor: visitor,
      session_id: "new_session_123"
    )

    assert new_session.started_at.present?
    assert_in_delta Time.current, new_session.started_at, 1.second
  end

  test "should initialize page_view_count to zero" do
    new_session = Session.create!(
      account: account,
      visitor: visitor,
      session_id: "new_session_456"
    )

    assert_equal 0, new_session.page_view_count
  end

  test "should increment page view count" do
    initial_count = session.page_view_count

    session.increment_page_views!

    assert_equal initial_count + 1, session.reload.page_view_count
  end

  test "should end session" do
    assert_nil session.ended_at

    session.end_session!

    assert session.ended_at.present?
    assert_in_delta Time.current, session.ended_at, 1.second
  end

  test "should check if session is active" do
    assert session.active?

    session.end_session!

    assert_not session.active?
  end

  test "should scope active sessions" do
    active_sessions = Session.active

    assert_includes active_sessions, session
    assert_not_includes active_sessions, sessions(:ended)
  end

  test "should scope recent sessions" do
    recent = Session.recent

    assert_includes recent, session
  end

  private

  def session
    @session ||= sessions(:one)
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def account
    @account ||= accounts(:one)
  end

  def other_visitor
    @other_visitor ||= visitors(:other_account_visitor)
  end

  def other_account
    @other_account ||= accounts(:two)
  end
end
