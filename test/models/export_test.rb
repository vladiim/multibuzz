# frozen_string_literal: true

require "test_helper"

class ExportTest < ActiveSupport::TestCase
  # ==========================================
  # Validations
  # ==========================================

  test "valid with required attributes" do
    export = build_export

    assert_predicate export, :valid?
  end

  test "requires account" do
    export = build_export(account: nil)

    assert_not export.valid?
    assert_includes export.errors[:account], "must exist"
  end

  test "requires export_type" do
    export = build_export(export_type: nil)

    assert_not export.valid?
    assert_includes export.errors[:export_type], "can't be blank"
  end

  test "export_type must be one of conversions, funnel, spend" do
    export = build_export(export_type: "invalid")

    assert_not export.valid?
    assert_includes export.errors[:export_type], "is not included in the list"
  end

  test "spend export_type is valid" do
    export = build_export(export_type: "spend")

    assert_predicate export, :valid?
  end

  # ==========================================
  # Status enum
  # ==========================================

  test "default status is pending" do
    export = build_export

    assert_predicate export, :pending?
  end

  test "status transitions through lifecycle" do
    export = create_export

    assert_predicate export, :pending?

    export.processing!

    assert_predicate export, :processing?

    export.completed!

    assert_predicate export, :completed?
  end

  test "can be marked as failed" do
    export = create_export
    export.failed!

    assert_predicate export, :failed?
  end

  # ==========================================
  # Prefix ID
  # ==========================================

  test "has exp_ prefix id" do
    export = create_export

    assert export.prefix_id.start_with?("exp_")
  end

  # ==========================================
  # Expiry
  # ==========================================

  test "expired? returns true when past expires_at" do
    export = create_export(expires_at: 1.minute.ago)

    assert_predicate export, :expired?
  end

  test "expired? returns false when before expires_at" do
    export = create_export(expires_at: 1.hour.from_now)

    assert_not export.expired?
  end

  test "expired? returns false when expires_at is nil" do
    export = create_export(expires_at: nil)

    assert_not export.expired?
  end

  # ==========================================
  # Blob management
  # ==========================================

  test "blob_key namespaces under account prefix id and export prefix id" do
    export = create_export

    assert_equal "accounts/#{account.prefix_id}/exports/#{export.prefix_id}.csv", export.blob_key
  end

  test "cleanup! purges attached blob and destroys record" do
    export = create_export
    export.csv.attach(
      io: StringIO.new("a,b\n1,2"),
      filename: "test.csv",
      content_type: "text/csv",
      key: export.blob_key
    )
    blob = export.csv.blob

    export.cleanup!

    assert_predicate export, :destroyed?
    assert_nil ActiveStorage::Blob.find_by(id: blob.id)
  end

  test "cleanup! handles missing attachment gracefully" do
    export = create_export

    assert_nothing_raised { export.cleanup! }
    assert_predicate export, :destroyed?
  end

  # ==========================================
  # Multi-account isolation
  # ==========================================

  test "scoped to account" do
    export = create_export
    other_account = accounts(:two)

    assert_not_includes other_account.exports, export
    assert_includes account.exports, export
  end

  private

  def account = @account ||= accounts(:one)

  def build_export(account: self.account, export_type: "conversions", **attrs)
    Export.new(account: account, export_type: export_type, **attrs)
  end

  def create_export(account: self.account, export_type: "conversions", **attrs)
    Export.create!(account: account, export_type: export_type, **attrs)
  end
end
