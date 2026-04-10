# frozen_string_literal: true

require "test_helper"

# rubocop:disable Minitest/AssertMatch, Minitest/RefuteMatch
# (assert_match expects a Regexp; SensitivePaths is a module, so the
# autocorrect would not work — these assertions stay literal.)
class SensitivePathsTest < ActiveSupport::TestCase
  test "matches /admin root" do
    assert SensitivePaths.match?("/admin")
  end

  test "matches /admin sub-routes" do
    assert SensitivePaths.match?("/admin/accounts")
  end

  test "matches /admin nested routes" do
    assert SensitivePaths.match?("/admin/billing/123")
  end

  test "does not match paths that merely start with /admin substring" do
    refute SensitivePaths.match?("/administration-tips")
  end

  test "matches api keys index route" do
    assert SensitivePaths.match?("/accounts/acct_abc123/api_keys")
  end

  test "matches api keys nested route" do
    assert SensitivePaths.match?("/accounts/acct_xyz/api_keys/new")
  end

  test "matches billing route" do
    assert SensitivePaths.match?("/accounts/acct_abc/billing")
  end

  test "matches integrations route" do
    assert SensitivePaths.match?("/accounts/acct_abc/integrations")
  end

  test "matches team root" do
    assert SensitivePaths.match?("/accounts/acct_abc/team")
  end

  test "matches team sub-routes" do
    assert SensitivePaths.match?("/accounts/acct_abc/team/invitations")
  end

  test "matches onboarding install" do
    assert SensitivePaths.match?("/onboarding/install")
  end

  test "matches onboarding install sub-route" do
    assert SensitivePaths.match?("/onboarding/install/ruby")
  end

  test "matches dashboard identities" do
    assert SensitivePaths.match?("/dashboard/identities")
  end

  test "matches dashboard identities show" do
    assert SensitivePaths.match?("/dashboard/identities/idt_abc123def")
  end

  test "matches dashboard conversion_detail" do
    assert SensitivePaths.match?("/dashboard/conversion_detail/conv_xyz")
  end

  test "matches dashboard exports" do
    assert SensitivePaths.match?("/dashboard/exports")
  end

  test "matches /edit actions on user routes" do
    assert SensitivePaths.match?("/accounts/acct_abc/users/user_xyz/edit")
  end

  test "matches /edit actions on any route" do
    assert SensitivePaths.match?("/something/else/edit")
  end

  test "matches paths containing live api key literal" do
    assert SensitivePaths.match?("/foo?key=sk_live_abc123")
  end

  test "matches paths containing test api key literal" do
    assert SensitivePaths.match?("/bar/sk_test_xyz789")
  end

  test "matches paths containing visitor prefix ids" do
    assert SensitivePaths.match?("/anything/vis_abc12345")
  end

  test "matches paths containing identity prefix ids" do
    assert SensitivePaths.match?("/anywhere/idt_xyz98765")
  end

  test "matches paths containing credential prefix ids" do
    assert SensitivePaths.match?("/some/path/cred_secret12")
  end

  test "does NOT match account prefix ids on dashboard route" do
    refute SensitivePaths.match?("/accounts/acct_abc/dashboard")
  end

  test "does NOT match account prefix ids on conversions route" do
    refute SensitivePaths.match?("/accounts/acct_abc/conversions")
  end

  test "does NOT match user prefix ids on their own" do
    refute SensitivePaths.match?("/dashboard/conversions/user_xyz123")
  end

  test "does NOT match session prefix ids on their own" do
    refute SensitivePaths.match?("/dashboard/sessions/sess_abc123")
  end

  test "does NOT match event prefix ids on their own" do
    refute SensitivePaths.match?("/dashboard/conversions/evt_abc12345")
  end

  test "does NOT match marketing site root" do
    refute SensitivePaths.match?("/")
  end

  test "does NOT match pricing page" do
    refute SensitivePaths.match?("/pricing")
  end

  test "does NOT match docs root" do
    refute SensitivePaths.match?("/docs")
  end

  test "does NOT match articles" do
    refute SensitivePaths.match?("/articles/something")
  end
end
# rubocop:enable Minitest/AssertMatch, Minitest/RefuteMatch
