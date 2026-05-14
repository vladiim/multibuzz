# frozen_string_literal: true

require "test_helper"

module Dashboard
  class ExportJobTest < ActiveSupport::TestCase
    setup do
      @export = Export.create!(
        account: account,
        export_type: "conversions",
        filter_params: { date_range: "30d", test_mode: false }
      )
    end

    teardown do
      Export.where(account: [ accounts(:one), accounts(:two) ]).find_each(&:cleanup!)
    end

    # ==========================================
    # Conversions export
    # ==========================================

    test "attaches CSV blob for conversions export" do
      perform_job

      @export.reload

      assert_predicate @export, :completed?
      assert_predicate @export.csv, :attached?
    end

    test "stores blob under accounts/<account_prefix>/exports/<export_prefix>.csv" do
      perform_job

      @export.reload

      assert_equal "accounts/#{account.prefix_id}/exports/#{@export.prefix_id}.csv", @export.csv.key
    end

    test "CSV contains valid headers for conversions export" do
      perform_job

      @export.reload
      csv = CSV.parse(@export.csv.download, headers: true)

      assert_equal Dashboard::CsvExportService::HEADERS, csv.headers
    end

    test "sets filename with export type and date" do
      perform_job

      @export.reload

      assert_equal "mbuzz-conversions-#{Date.current}.csv", @export.filename
    end

    test "sets completed_at timestamp" do
      perform_job

      @export.reload

      assert_not_nil @export.completed_at
      assert_in_delta Time.current, @export.completed_at, 5.seconds
    end

    test "sets expires_at to 1 hour from completion" do
      perform_job

      @export.reload

      assert_not_nil @export.expires_at
      assert_in_delta 1.hour.from_now, @export.expires_at, 5.seconds
    end

    test "export reaches completed status" do
      assert_predicate @export, :pending?

      perform_job

      @export.reload

      assert_predicate @export, :completed?
    end

    # ==========================================
    # Funnel export
    # ==========================================

    test "attaches CSV blob for funnel export" do
      @export.update!(export_type: "funnel")

      perform_job

      @export.reload

      assert_predicate @export, :completed?
      assert_predicate @export.csv, :attached?
    end

    test "funnel CSV contains valid headers" do
      @export.update!(export_type: "funnel")

      perform_job

      @export.reload
      csv = CSV.parse(@export.csv.download, headers: true)

      assert_equal Dashboard::FunnelCsvExportService::HEADERS, csv.headers
    end

    test "funnel filename includes funnel type" do
      @export.update!(export_type: "funnel")

      perform_job

      @export.reload

      assert_equal "mbuzz-funnel-#{Date.current}.csv", @export.filename
    end

    # ==========================================
    # Spend export
    # ==========================================

    test "attaches CSV blob for spend export" do
      @export.update!(export_type: "spend")

      perform_job

      @export.reload

      assert_predicate @export, :completed?
      assert_predicate @export.csv, :attached?
    end

    test "spend CSV contains valid headers" do
      @export.update!(export_type: "spend")

      perform_job

      @export.reload
      csv = CSV.parse(@export.csv.download, headers: true)

      assert_equal Dashboard::SpendCsvExportService::HEADERS, csv.headers
    end

    test "spend filename uses spend prefix" do
      @export.update!(export_type: "spend")

      perform_job

      @export.reload

      assert_equal "mbuzz-spend-#{Date.current}.csv", @export.filename
    end

    # ==========================================
    # Turbo Stream broadcast
    # ==========================================

    test "broadcasts download link on completion" do
      stream = "export_#{@export.prefix_id}"

      assert_broadcasts(stream, 1) do
        perform_job
      end
    end

    # ==========================================
    # Idempotency — defense against Solid Queue redelivery
    # ==========================================

    test "perform is a no-op for an already-:completed export (no status change)" do
      @export.update!(status: :completed, completed_at: 5.minutes.ago, expires_at: 55.minutes.from_now)
      original_updated_at = @export.reload.updated_at

      perform_job

      assert_equal original_updated_at, @export.reload.updated_at
    end

    test "perform does not broadcast for an already-:completed export" do
      @export.update!(status: :completed, completed_at: 5.minutes.ago, expires_at: 55.minutes.from_now)
      stream = "export_#{@export.prefix_id}"

      assert_broadcasts(stream, 0) do
        perform_job
      end
    end

    # ==========================================
    # Filter params passthrough
    # ==========================================

    test "passes stored filter params to service" do
      @export.update!(filter_params: {
        "date_range" => "7d",
        "channels" => [ Channels::PAID_SEARCH ],
        "test_mode" => true,
        "funnel" => "sales"
      })

      perform_job

      @export.reload

      assert_predicate @export, :completed?
    end

    test "handles custom date range after JSONB roundtrip" do
      @export.update!(filter_params: {
        "date_range" => { "start_date" => "2026-02-01", "end_date" => "2026-02-28" },
        "test_mode" => false
      })

      perform_job

      @export.reload

      assert_predicate @export, :completed?
    end

    # ==========================================
    # Multi-account isolation
    # ==========================================

    test "generates export scoped to the export's account" do
      other_account = accounts(:two)
      other_export = Export.create!(
        account: other_account,
        export_type: "conversions",
        filter_params: { date_range: "30d", test_mode: false }
      )

      perform_job(other_export)

      other_export.reload

      assert_predicate other_export, :completed?
      csv = CSV.parse(other_export.csv.download, headers: true)
      # Should not contain account :one's data
      csv.each do |row|
        assert_not_equal account.id, row["account_id"]
      end
    end

    private

    def account = @account ||= accounts(:one)

    def perform_job(export = @export)
      Dashboard::ExportJob.perform_now(export.id)
    end
  end
end
