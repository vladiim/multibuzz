# frozen_string_literal: true

require "test_helper"

class Visitors::DeduplicationServiceTest < ActiveSupport::TestCase
  # --- Core merge behavior ---

  test "merges duplicate visitors with same fingerprint created in burst" do
    v1, v2, v3 = create_burst_visitors(fingerprint: fingerprint_a, count: 3)

    result = service.call

    assert result[:success]
    assert_equal 2, result[:stats][:visitors_merged]
    assert Visitor.exists?(v1.id), "Canonical visitor should survive"
    refute Visitor.exists?(v2.id), "Duplicate should be deleted"
    refute Visitor.exists?(v3.id), "Duplicate should be deleted"
  end

  test "reassigns sessions from duplicates to canonical visitor" do
    v1, v2 = create_burst_visitors(fingerprint: fingerprint_a, count: 2)
    s2 = account.sessions.find_by(visitor_id: v2.id)

    service.call

    assert_equal v1.id, s2.reload.visitor_id
  end

  test "reassigns events from duplicates to canonical visitor" do
    v1, v2 = create_burst_visitors(fingerprint: fingerprint_a, count: 2)
    s2 = account.sessions.find_by(visitor_id: v2.id)
    event = account.events.create!(
      visitor: v2, session: s2,
      event_type: "page_view", occurred_at: Time.current,
      properties: { url: "https://example.com" }
    )

    service.call

    assert_equal v1.id, event.reload.visitor_id
  end

  test "reassigns conversions from duplicates to canonical visitor" do
    v1, v2 = create_burst_visitors(fingerprint: fingerprint_a, count: 2)
    conversion = account.conversions.create!(
      visitor: v2, conversion_type: "purchase",
      revenue: 99.99, converted_at: Time.current
    )

    service.call

    assert_equal v1.id, conversion.reload.visitor_id
  end

  test "preserves identity link from duplicate" do
    v1, v2 = create_burst_visitors(fingerprint: fingerprint_a, count: 2)
    identity = account.identities.create!(
      external_id: "user_123",
      first_identified_at: Time.current,
      last_identified_at: Time.current
    )
    v2.update!(identity: identity)

    service.call

    assert_equal identity.id, v1.reload.identity_id,
      "Canonical visitor should inherit identity from duplicate"
  end

  test "does not overwrite existing identity on canonical" do
    v1, v2 = create_burst_visitors(fingerprint: fingerprint_a, count: 2)
    original_identity = account.identities.create!(
      external_id: "user_original",
      first_identified_at: Time.current,
      last_identified_at: Time.current
    )
    other_identity = account.identities.create!(
      external_id: "user_other",
      first_identified_at: Time.current,
      last_identified_at: Time.current
    )
    v1.update!(identity: original_identity)
    v2.update!(identity: other_identity)

    service.call

    assert_equal original_identity.id, v1.reload.identity_id,
      "Should not overwrite canonical's existing identity"
  end

  # --- Boundary conditions ---

  test "keeps earliest visitor as canonical" do
    v1 = create_visitor_with_session("vis_early", fingerprint_a, created_offset: -2.seconds)
    v2 = create_visitor_with_session("vis_late", fingerprint_a, created_offset: 0.seconds)

    service.call

    assert Visitor.exists?(v1.id), "Earlier visitor should be canonical"
    refute Visitor.exists?(v2.id), "Later visitor should be merged"
  end

  test "does not merge visitors with different fingerprints" do
    v1 = create_visitor_with_session("vis_fp_a", fingerprint_a)
    v2 = create_visitor_with_session("vis_fp_b", fingerprint_b)

    result = service.call

    assert result[:success]
    assert_equal 0, result[:stats][:visitors_merged]
    assert Visitor.exists?(v1.id)
    assert Visitor.exists?(v2.id)
  end

  test "does not merge visitors created far apart in time" do
    now = Time.current
    v1 = create_visitor_with_session("vis_old", fingerprint_a, created_at: now - 2.minutes)
    v2 = create_visitor_with_session("vis_new", fingerprint_a, created_at: now)

    result = service.call

    assert_equal 0, result[:stats][:visitors_merged],
      "Visitors created >30s apart should not be merged"
    assert Visitor.exists?(v1.id)
    assert Visitor.exists?(v2.id)
  end

  test "handles multiple fingerprint groups independently" do
    va1, va2 = create_burst_visitors(fingerprint: fingerprint_a, count: 2, prefix: "vis_a")
    vb1, vb2, vb3 = create_burst_visitors(fingerprint: fingerprint_b, count: 3, prefix: "vis_b")

    result = service.call

    assert_equal 3, result[:stats][:visitors_merged], "1 from group A + 2 from group B"
    assert Visitor.exists?(va1.id)
    assert Visitor.exists?(vb1.id)
  end

  # --- Dry run ---

  test "dry run reports stats but makes no changes" do
    v1, v2 = create_burst_visitors(fingerprint: fingerprint_a, count: 2)

    result = Visitors::DeduplicationService.new(account, dry_run: true).call

    assert result[:success]
    assert_equal 1, result[:stats][:visitors_merged]
    assert Visitor.exists?(v1.id), "Dry run should not delete anything"
    assert Visitor.exists?(v2.id), "Dry run should not delete anything"
  end

  # --- Edge cases ---

  test "skips fingerprints with only one visitor" do
    create_visitor_with_session("vis_solo", fingerprint_a)

    result = service.call

    assert_equal 0, result[:stats][:visitors_merged]
  end

  test "handles account with no sessions" do
    result = service.call

    assert result[:success]
    assert_equal 0, result[:stats][:fingerprints_checked]
  end

  test "updates canonical first_seen_at to earliest across all merged visitors" do
    early_time = 1.hour.ago
    v1, v2 = create_burst_visitors(fingerprint: fingerprint_a, count: 2)
    v2.update_column(:first_seen_at, early_time)

    service.call

    assert_in_delta early_time, v1.reload.first_seen_at, 1.second
  end

  private

  def service
    @service ||= Visitors::DeduplicationService.new(account)
  end

  def account
    @account ||= accounts(:one)
  end

  def fingerprint_a
    @fingerprint_a ||= Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]
  end

  def fingerprint_b
    @fingerprint_b ||= Digest::SHA256.hexdigest("10.0.0.2|Firefox/130")[0, 32]
  end

  def create_burst_visitors(fingerprint:, count:, prefix: "vis_burst")
    now = Time.current
    count.times.map do |i|
      create_visitor_with_session("#{prefix}_#{i}", fingerprint, created_at: now + i.seconds)
    end
  end

  def create_visitor_with_session(vid, fingerprint, created_at: Time.current, created_offset: nil)
    ts = created_offset ? Time.current + created_offset : created_at
    visitor = account.visitors.create!(
      visitor_id: vid, first_seen_at: ts, last_seen_at: ts,
      created_at: ts, updated_at: ts
    )
    account.sessions.create!(
      visitor: visitor, session_id: "sess_#{vid}",
      device_fingerprint: fingerprint,
      started_at: ts, last_activity_at: ts,
      created_at: ts, updated_at: ts
    )
    visitor
  end
end
