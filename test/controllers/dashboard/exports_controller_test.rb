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

  test "create with spend export type" do
    sign_in
    post dashboard_export_path, params: { export_type: "spend" }

    export = Export.last

    assert_equal "spend", export.export_type
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

  test "download redirects to signed storage url for completed export" do
    sign_in
    export = create_completed_export

    get dashboard_export_download_path(id: export.prefix_id)

    assert_response :redirect
    assert_includes response.location, export.filename
  end

  test "download returns 410 when blob is missing" do
    sign_in
    export = Export.create!(
      account: account,
      export_type: "conversions",
      status: :completed,
      filename: "mbuzz-conversions-#{Date.current}.csv",
      completed_at: Time.current,
      expires_at: 1.hour.from_now
    )

    get dashboard_export_download_path(id: export.prefix_id)

    assert_response :gone
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
  # Dashboard UI: single tab-aware Download CSV
  # ==========================================

  test "dashboard has export dropdown trigger" do
    sign_in
    get dashboard_path

    assert_response :success
    assert_select "button", text: /Export/
  end

  test "dashboard renders a single Download CSV submit row" do
    sign_in
    get dashboard_path

    assert_response :success
    download_buttons = css_select("[data-export-button-target='container'] button[type='submit']")

    assert_equal 1, download_buttons.size, "expected exactly one CSV submit button in the dropdown"
    assert_match(/Download CSV/i, download_buttons.first.text)
  end

  test "dashboard no longer renders separate Conversions CSV / Funnel CSV rows" do
    sign_in
    get dashboard_path

    assert_response :success
    assert_select "button", text: "Conversions CSV", count: 0
    assert_select "button", text: "Funnel CSV", count: 0
  end

  test "dashboard no longer renders API Extract waitlist row in export dropdown" do
    sign_in
    get dashboard_path

    assert_response :success
    dropdown_html = css_select("[data-export-button-target='container']").first&.to_html.to_s

    assert_no_match(/API Extract/i, dropdown_html)
    assert_no_match(/Coming soon/i, dropdown_html)
  end

  test "dashboard hidden export_type input defaults to conversions" do
    sign_in
    get dashboard_path

    assert_response :success
    assert_select "[data-controller~='export-button'] input[name='export_type'][value='conversions']"
  end

  test "dashboard hidden export_type input reflects ?tab= param" do
    sign_in
    get dashboard_path(tab: DashboardTabs::SPEND)

    assert_response :success
    assert_select "[data-controller~='export-button'] input[name='export_type'][value='spend']"
  end

  test "dashboard hidden export_type input falls back to conversions when tab is events" do
    sign_in
    get dashboard_path(tab: DashboardTabs::EVENTS)

    assert_response :success
    # Events tab is not exportable; the input still posts a valid value but the
    # button is hidden client-side via Stimulus.
    assert_select "[data-controller~='export-button'] input[name='export_type'][value='conversions']"
  end

  test "dashboard exposes initial tab via export-button data attribute" do
    sign_in
    get dashboard_path(tab: DashboardTabs::FUNNEL)

    assert_response :success
    assert_select "[data-controller~='export-button'][data-export-button-initial-tab-value='funnel']"
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

    export.csv.attach(
      io: StringIO.new(CSV.generate { |csv| csv << %w[date type name] }),
      filename: export.filename,
      content_type: "text/csv",
      key: export.blob_key
    )

    export
  end
end
