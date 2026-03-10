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

  test "export_type must be conversions or funnel" do
    export = build_export(export_type: "invalid")

    assert_not export.valid?
    assert_includes export.errors[:export_type], "is not included in the list"
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
  # File management
  # ==========================================

  test "cleanup! deletes file and record" do
    export = create_export
    file_path = Rails.root.join("tmp/exports/test_cleanup_#{SecureRandom.hex(4)}.csv")
    FileUtils.mkdir_p(File.dirname(file_path))
    File.write(file_path, "test")
    export.update!(file_path: file_path.to_s)

    export.cleanup!

    assert_not File.exist?(file_path)
    assert_predicate export, :destroyed?
  end

  test "cleanup! handles missing file gracefully" do
    export = create_export(file_path: "/tmp/nonexistent.csv")

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
