# frozen_string_literal: true

require "test_helper"

module Identities
  class IdentificationServiceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      Rails.cache.clear
    end

    # Basic identification tests

    test "creates new identity when user_id does not exist" do
      assert_difference -> { account.identities.unscope(where: :is_test).count } do
        result = service(user_id: "new_user_999").call

        assert result[:success]
        assert_predicate result[:identity_id], :present?
      end
    end

    test "updates existing identity traits" do
      existing = create_test_identity(external_id: "existing_user")

      assert_no_difference -> { account.identities.unscope(where: :is_test).count } do
        result = service(user_id: "existing_user", traits: { name: "Updated" }).call

        assert result[:success]
      end

      assert_equal "Updated", existing.reload.traits["name"]
    end

    test "links visitor to identity when visitor_id provided" do
      visitor = create_visitor(visitor_id: "vis_to_link")

      result = service(user_id: "link_user", visitor_id: "vis_to_link").call

      assert result[:success]
      assert result[:visitor_linked]
      assert_not_nil visitor.reload.identity
    end

    test "returns visitor_linked false when visitor not found" do
      result = service(user_id: "some_user", visitor_id: "nonexistent").call

      assert result[:success]
      refute result[:visitor_linked]
    end

    test "returns error when user_id missing" do
      result = service(user_id: nil).call

      assert_not result[:success]
      assert_includes result[:errors], "user_id is required"
    end

    # Traits merge tests

    test "merges new traits with existing traits" do
      existing = create_test_identity(external_id: "merge_user", traits: { plan: "pro", role: "admin" })

      result = service(user_id: "merge_user", traits: { email: "a@b.com" }).call

      assert result[:success]
      reloaded = existing.reload.traits

      assert_equal "pro", reloaded["plan"]
      assert_equal "admin", reloaded["role"]
      assert_equal "a@b.com", reloaded["email"]
    end

    test "overwrites matching trait keys on merge" do
      existing = create_test_identity(external_id: "overwrite_user", traits: { plan: "free" })

      result = service(user_id: "overwrite_user", traits: { plan: "pro" }).call

      assert result[:success]
      assert_equal "pro", existing.reload.traits["plan"]
    end

    test "preserves traits when empty traits provided" do
      existing = create_test_identity(external_id: "empty_traits_user", traits: { plan: "pro" })

      result = service(user_id: "empty_traits_user", traits: {}).call

      assert result[:success]
      assert_equal "pro", existing.reload.traits["plan"]
    end

    # Hashed PII population

    test "populates email_sha256 from canonical email trait" do
      service(user_id: "pii_user", traits: { email: "  Jane@Example.COM  " }).call
      identity = account.identities.unscope(where: :is_test).find_by(external_id: "pii_user")

      assert_equal Identities::Normaliser.hash_email("jane@example.com"), identity.email_sha256
    end

    test "populates phone_e164_sha256 from canonical phone trait" do
      service(user_id: "pii_phone_user", traits: { phone: "+1 (415) 555-1234" }).call
      identity = account.identities.unscope(where: :is_test).find_by(external_id: "pii_phone_user")

      assert_equal Identities::Normaliser.hash_phone("+14155551234"), identity.phone_e164_sha256
    end

    test "populates first_name_sha256 and last_name_sha256 with diacritics stripped" do
      service(user_id: "pii_name_user", traits: { first_name: "  José  ", last_name: "Müller" }).call
      identity = account.identities.unscope(where: :is_test).find_by(external_id: "pii_name_user")

      assert_equal Identities::Normaliser.hash_name("jose"), identity.first_name_sha256
      assert_equal Identities::Normaliser.hash_name("muller"), identity.last_name_sha256
    end

    test "leaves hashed columns nil when canonical fields absent" do
      service(user_id: "no_pii_user", traits: { plan: "pro" }).call
      identity = account.identities.unscope(where: :is_test).find_by(external_id: "no_pii_user")

      assert_nil identity.email_sha256
      assert_nil identity.phone_e164_sha256
      assert_nil identity.first_name_sha256
      assert_nil identity.last_name_sha256
    end

    test "preserves existing hashed columns when subsequent identify omits the field" do
      existing = create_test_identity(external_id: "preserve_user")
      service(user_id: "preserve_user", traits: { email: "first@example.com" }).call
      service(user_id: "preserve_user", traits: { plan: "pro" }).call

      assert_equal Identities::Normaliser.hash_email("first@example.com"), existing.reload.email_sha256
    end

    test "overwrites hashed columns when subsequent identify provides a new value" do
      existing = create_test_identity(external_id: "overwrite_pii_user")
      service(user_id: "overwrite_pii_user", traits: { email: "first@example.com" }).call
      service(user_id: "overwrite_pii_user", traits: { email: "second@example.com" }).call

      assert_equal Identities::Normaliser.hash_email("second@example.com"), existing.reload.email_sha256
    end

    test "raw email value still lands in traits JSONB for backwards compatibility" do
      service(user_id: "compat_user", traits: { email: "user@example.com" }).call
      identity = account.identities.unscope(where: :is_test).find_by(external_id: "compat_user")

      assert_equal "user@example.com", identity.traits["email"]
    end

    test "deep merges nested trait hashes" do
      existing = create_test_identity(
        external_id: "nested_user",
        traits: { address: { city: "New York", state: "NY" } }
      )

      result = service(user_id: "nested_user", traits: { address: { zip: "10001" } }).call

      assert result[:success]
      address = existing.reload.traits["address"]

      assert_equal "New York", address["city"]
      assert_equal "NY", address["state"]
      assert_equal "10001", address["zip"]
    end

    # Retroactive attribution detection tests

    test "identifies conversions needing reattribution when new sessions in lookback" do
      test_identity = create_test_identity(external_id: "reattr_user_1")
      existing_visitor = create_visitor(visitor_id: "vis_existing", identity: test_identity)
      create_session_for_visitor(existing_visitor, started_at: 15.days.ago)

      conversion = create_conversion(visitor: existing_visitor, converted_at: 5.days.ago)

      new_visitor = create_visitor(visitor_id: "vis_new_device")
      create_session_for_visitor(new_visitor, started_at: 10.days.ago)

      svc = service(user_id: test_identity.external_id, visitor_id: "vis_new_device")
      svc.call

      conversions = svc.send(:conversions_needing_reattribution)

      assert_includes conversions, conversion
    end

    test "does not identify conversions when no conversions exist" do
      test_identity = create_test_identity(external_id: "reattr_user_2")
      existing_visitor = create_visitor(visitor_id: "vis_no_conv", identity: test_identity)

      new_visitor = create_visitor(visitor_id: "vis_new_no_conv")
      create_session_for_visitor(new_visitor, started_at: 10.days.ago)

      svc = service(user_id: test_identity.external_id, visitor_id: "vis_new_no_conv")
      svc.call

      conversions = svc.send(:conversions_needing_reattribution)

      assert_empty conversions
    end

    test "does not identify conversions when sessions outside lookback window" do
      test_identity = create_test_identity(external_id: "reattr_user_3")
      existing_visitor = create_visitor(visitor_id: "vis_outside", identity: test_identity)
      create_session_for_visitor(existing_visitor, started_at: 20.days.ago)

      create_conversion(visitor: existing_visitor, converted_at: 5.days.ago)

      new_visitor = create_visitor(visitor_id: "vis_old_session")
      create_session_for_visitor(new_visitor, started_at: 60.days.ago)

      svc = service(user_id: test_identity.external_id, visitor_id: "vis_old_session")
      svc.call

      conversions = svc.send(:conversions_needing_reattribution)

      assert_empty conversions
    end

    test "identifies multiple conversions when applicable" do
      test_identity = create_test_identity(external_id: "reattr_user_4")
      existing_visitor = create_visitor(visitor_id: "vis_multi", identity: test_identity)
      create_session_for_visitor(existing_visitor, started_at: 25.days.ago)

      conv1 = create_conversion(visitor: existing_visitor, converted_at: 10.days.ago)
      conv2 = create_conversion(visitor: existing_visitor, converted_at: 5.days.ago)

      new_visitor = create_visitor(visitor_id: "vis_applies_both")
      create_session_for_visitor(new_visitor, started_at: 15.days.ago)

      svc = service(user_id: test_identity.external_id, visitor_id: "vis_applies_both")
      svc.call

      conversions = svc.send(:conversions_needing_reattribution)

      assert_equal 2, conversions.count
      assert_includes conversions, conv1
      assert_includes conversions, conv2
    end

    test "only identifies conversions where new sessions apply" do
      test_identity = create_test_identity(external_id: "reattr_user_5")
      existing_visitor = create_visitor(visitor_id: "vis_selective", identity: test_identity)

      # Conv1: 5 days ago - new session at 20 days ago IS in 30-day lookback
      conv1 = create_conversion(visitor: existing_visitor, converted_at: 5.days.ago)
      # Conv2: 60 days ago - new session at 20 days ago is NOT in lookback
      conv2 = create_conversion(visitor: existing_visitor, converted_at: 60.days.ago)

      new_visitor = create_visitor(visitor_id: "vis_selective_sessions")
      create_session_for_visitor(new_visitor, started_at: 20.days.ago)

      svc = service(user_id: test_identity.external_id, visitor_id: "vis_selective_sessions")
      svc.call

      conversions = svc.send(:conversions_needing_reattribution)

      assert_equal 1, conversions.count
      assert_includes conversions, conv1
      assert_not_includes conversions, conv2
    end

    # Session activity tracking tests

    test "updates session last_activity_at when visitor linked to identity" do
      visitor = create_visitor(visitor_id: "vis_activity_track")
      session = create_session_for_visitor(visitor, started_at: 1.hour.ago)
      session.update!(last_activity_at: 1.hour.ago)
      old_activity = session.last_activity_at

      result = service(user_id: "activity_user", visitor_id: "vis_activity_track").call

      assert result[:success]
      assert_operator session.reload.last_activity_at, :>, old_activity
      assert_in_delta Time.current.to_i, session.last_activity_at.to_i, 2
    end

    test "handles visitor with no sessions when updating activity" do
      visitor = create_visitor(visitor_id: "vis_no_session_activity")

      result = service(user_id: "no_session_user", visitor_id: "vis_no_session_activity").call

      assert result[:success]
      assert result[:visitor_linked]
    end

    # Reattribution enqueue tests

    test "enqueues exactly one BatchReattributionJob per identification covering all eligible conversions" do
      test_identity = create_test_identity(external_id: "batch_user_1")
      existing_visitor = create_visitor(visitor_id: "vis_existing_batch", identity: test_identity)
      create_session_for_visitor(existing_visitor, started_at: 25.days.ago)

      conv_a = create_conversion(visitor: existing_visitor, converted_at: 10.days.ago)
      conv_b = create_conversion(visitor: existing_visitor, converted_at: 5.days.ago)

      create_visitor(visitor_id: "vis_new_batch")
      create_session_for_visitor(account.visitors.find_by(visitor_id: "vis_new_batch"), started_at: 15.days.ago)

      assert_enqueued_jobs 1, only: Conversions::BatchReattributionJob do
        service(user_id: test_identity.external_id, visitor_id: "vis_new_batch").call
      end

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |j| j["job_class"] == "Conversions::BatchReattributionJob" }

      assert_equal [ conv_a.id, conv_b.id ].sort, enqueued["arguments"].first.sort
    end

    test "enqueues no reattribution job when there are no eligible conversions" do
      create_visitor(visitor_id: "vis_first_link")

      assert_no_enqueued_jobs only: [ Conversions::BatchReattributionJob, Conversions::ReattributionJob ] do
        service(user_id: "first_link_user", visitor_id: "vis_first_link").call
      end
    end

    private

    def service(user_id:, visitor_id: nil, traits: {})
      IdentificationService.new(
        account,
        { user_id: user_id, visitor_id: visitor_id, traits: traits },
        is_test: true
      )
    end

    def account
      @account ||= accounts(:one)
    end

    def create_test_identity(external_id:, traits: {})
      account.identities.unscope(where: :is_test).create!(
        external_id: external_id,
        traits: traits,
        first_identified_at: Time.current,
        last_identified_at: Time.current,
        is_test: true
      )
    end

    def create_visitor(visitor_id:, identity: nil)
      account.visitors.unscope(where: :is_test).create!(
        visitor_id: visitor_id,
        first_seen_at: Time.current,
        last_seen_at: Time.current,
        identity: identity,
        is_test: true
      )
    end

    def create_session_for_visitor(visitor, started_at:)
      Session.create!(
        account: account,
        visitor: visitor,
        session_id: SecureRandom.hex(16),
        started_at: started_at,
        channel: "organic_search",
        initial_utm: { "utm_source" => "google" },
        is_test: true
      )
    end

    def create_conversion(visitor:, converted_at:)
      Conversion.create!(
        account: account,
        visitor: visitor,
        session_id: 1,
        event_id: 1,
        conversion_type: "purchase",
        converted_at: converted_at,
        journey_session_ids: [],
        is_test: true
      )
    end
  end
end
