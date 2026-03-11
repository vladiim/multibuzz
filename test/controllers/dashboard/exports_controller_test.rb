# frozen_string_literal: true

require "test_helper"

class Dashboard::ExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    accounts(:one).update!(onboarding_progress: (1 << Account::Onboarding::ONBOARDING_STEPS.size) - 1)
  end

  teardown do
    Export.where(account: [ accounts(:one), accounts(:two) ]).find_each(&:cleanup!)
  end

  # ==========================================
  # Authentication
  # ==========================================

  test "requires authentication for create" do
    post dashboard_export_path

    assert_response :redirect
  end

  test "requires authentication for show" do
    export = create_completed_export

    get dashboard_export_status_path(id: export.prefix_id)

    assert_response :redirect
  end

  test "requires authentication for download" do
    export = create_completed_export

    get dashboard_export_download_path(id: export.prefix_id)

    assert_response :redirect
  end

  # ==========================================
  # Create (enqueue export)
  # ==========================================

  test "create enqueues export job" do
    sign_in

    assert_enqueued_with(job: Dashboard::ExportJob) do
      post dashboard_export_path, params: { export_type: "conversions" }
    end
  end

  test "create redirects to export status page" do
    sign_in
    post dashboard_export_path, params: { export_type: "conversions" }

    export = Export.last

    assert_redirected_to dashboard_export_status_path(id: export.prefix_id)
  end

  test "create persists export record" do
    sign_in

    assert_difference "Export.count", 1 do
      post dashboard_export_path, params: { export_type: "conversions" }
    end

    export = Export.last

    assert_equal account.id, export.account_id
    assert_predicate export, :pending?
  end

  test "create stores serialized filter params" do
    sign_in
    post dashboard_export_path, params: {
      export_type: "funnel",
      date_range: "7d",
      channels: [ Channels::PAID_SEARCH, Channels::EMAIL ],
      funnel: "sales",
      view_mode: "test"
    }

    export = Export.last

    assert_equal "7d", export.filter_params["date_range"]
    assert_equal "sales", export.filter_params["funnel"]
    assert export.filter_params["test_mode"]
  end

  test "create defaults to conversions export type" do
    sign_in
    post dashboard_export_path

    export = Export.last

    assert_equal "conversions", export.export_type
  end

  test "create with funnel export type" do
    sign_in
    post dashboard_export_path, params: { export_type: "funnel" }

    export = Export.last

    assert_equal "funnel", export.export_type
  end

  # ==========================================
  # Show (export status page)
  # ==========================================

  test "show renders processing state for pending export" do
    sign_in
    export = Export.create!(account: account, export_type: "conversions")

    get dashboard_export_status_path(id: export.prefix_id)

    assert_response :success
    assert_select "h2", "Preparing your export"
  end

  test "show renders processing state for processing export" do
    sign_in
    export = Export.create!(account: account, export_type: "conversions", status: :processing)

    get dashboard_export_status_path(id: export.prefix_id)

    assert_response :success
    assert_select "h2", "Preparing your export"
  end

  test "show renders download button for completed export" do
    sign_in
    export = create_completed_export

    get dashboard_export_status_path(id: export.prefix_id)

    assert_response :success
    assert_select "h2", "Export ready"
    assert_select "a[href=?]", dashboard_export_download_path(id: export.prefix_id)
  end

  test "show renders error for failed export" do
    sign_in
    export = Export.create!(account: account, export_type: "conversions", status: :failed)

    get dashboard_export_status_path(id: export.prefix_id)

    assert_response :success
    assert_select "h2", "Export failed"
  end

  test "show subscribes to export turbo stream" do
    sign_in
    export = Export.create!(account: account, export_type: "conversions")

    get dashboard_export_status_path(id: export.prefix_id)

    assert_response :success
    assert_select "turbo-cable-stream-source[signed-stream-name]"
  end

  test "show returns 404 for other account's export" do
    sign_in
    other_export = Export.create!(account: accounts(:two), export_type: "conversions")

    get dashboard_export_status_path(id: other_export.prefix_id)

    assert_response :not_found
  end

  # ==========================================
  # Download (file delivery)
  # ==========================================

  test "download sends completed export file" do
    sign_in
    export = create_completed_export

    get dashboard_export_download_path(id: export.prefix_id)

    assert_response :success
    assert_equal "text/csv", response.content_type
    assert_match "attachment", response.headers["Content-Disposition"]
  end

  test "download returns 404 for pending export" do
    sign_in
    export = Export.create!(account: account, export_type: "conversions")

    get dashboard_export_download_path(id: export.prefix_id)

    assert_response :not_found
  end

  test "download returns 410 for expired export" do
    sign_in
    export = create_completed_export(expires_at: 1.minute.ago)

    get dashboard_export_download_path(id: export.prefix_id)

    assert_response :gone
  end

  test "download returns 404 for other account's export" do
    sign_in
    other_export = create_completed_export(account: accounts(:two))

    get dashboard_export_download_path(id: other_export.prefix_id)

    assert_response :not_found
  end

  # ==========================================
  # Dashboard UI
  # ==========================================

  test "dashboard has export dropdown" do
    sign_in
    get dashboard_path

    assert_response :success
    assert_select "button", text: /Export/
  end

  private

  def sign_in
    post login_path, params: { email: users(:one).email, password: "password123" }
  end

  def account = @account ||= accounts(:one)

  def create_completed_export(account: self.account, expires_at: 1.hour.from_now)
    export = Export.create!(
      account: account,
      export_type: "conversions",
      status: :completed,
      filename: "mbuzz-conversions-#{Date.current}.csv",
      completed_at: Time.current,
      expires_at: expires_at
    )

    # Write a real file
    dir = Rails.root.join("tmp/exports")
    FileUtils.mkdir_p(dir)
    file_path = dir.join("#{export.prefix_id}.csv")
    File.write(file_path, CSV.generate { |csv| csv << %w[date type name] })
    export.update!(file_path: file_path.to_s)

    export
  end
end
