require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "should be valid with valid attributes" do
    assert account.valid?
  end

  test "should require name" do
    account.name = nil

    assert_not account.valid?
    assert_includes account.errors[:name], "can't be blank"
  end

  test "should require slug" do
    account.slug = nil

    assert_not account.valid?
    assert_includes account.errors[:slug], "can't be blank"
  end

  test "should require unique slug" do
    duplicate = Account.new(
      name: "Acme Corp",
      slug: account.slug,
      status: "active"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "should validate slug format allows valid formats" do
    valid_slugs = %w[acme acme-inc acme-123 acme2024]

    valid_slugs.each do |slug|
      account.slug = slug
      assert account.valid?, "#{slug} should be valid"
    end
  end

  test "should validate slug format rejects invalid formats" do
    invalid_slugs = ["Acme Inc", "acme_inc", "acme inc", "acme@inc", "ACME"]

    invalid_slugs.each do |slug|
      account.slug = slug
      assert_not account.valid?, "#{slug} should be invalid"
      assert_includes account.errors[:slug], "must be lowercase letters, numbers, and hyphens only"
    end
  end

  test "should default status to active" do
    new_account = Account.new(name: "New Account", slug: "new-account")

    assert new_account.active?
  end

  test "should allow changing status with enum methods" do
    account.suspended!
    assert account.suspended?

    account.cancelled!
    assert account.cancelled?

    account.active!
    assert account.active?
  end

  test "should have many api_keys" do
    assert_respond_to account, :api_keys
  end

  test "should have many visitors" do
    assert_respond_to account, :visitors
  end

  test "should have many sessions" do
    assert_respond_to account, :sessions
  end

  test "should have many events" do
    assert_respond_to account, :events
  end

  test "should store settings as jsonb" do
    account.update!(settings: { timezone: "UTC", currency: "USD" })
    account.reload

    assert_equal "UTC", account.settings["timezone"]
    assert_equal "USD", account.settings["currency"]
  end

  test "should be active" do
    account.status = "active"
    assert account.active?
  end

  test "should be suspended" do
    account.status = "suspended"
    assert account.suspended?
  end

  test "should be cancelled" do
    account.status = "cancelled"
    assert account.cancelled?
  end

  test "should auto-create default attribution models on create" do
    new_account = Account.create!(name: "Test Account", slug: "test-auto-#{SecureRandom.hex(4)}")

    assert_equal AttributionAlgorithms::DEFAULTS.size, new_account.attribution_models.count

    AttributionAlgorithms::DEFAULTS.each do |algorithm|
      model = new_account.attribution_models.find_by(name: algorithm)
      assert model.present?, "Expected attribution model '#{algorithm}' to exist"
      assert_equal algorithm, model.algorithm, "Expected algorithm to be set to '#{algorithm}'"
      assert model.preset?, "Expected model_type to be preset"
    end

    assert new_account.attribution_models.all?(&:is_active?)
  end

  private

  def account
    @account ||= accounts(:one)
  end
end
