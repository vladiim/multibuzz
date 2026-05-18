import { Controller } from "@hotwired/stimulus"

// Binds the dashboard's "Download CSV" row to the active tab.
//
// - Trigger stays visible on all tabs — API + MCP rows are tab-agnostic.
// - On non-exportable tabs (Events) the CSV row hides; API + MCP remain.
// - Rewrites the hidden export_type input to match the active tab so the
//   submitted form posts the right export_type to /dashboard/export.
//
// Lives on the same element as the outer toggle controller; tab buttons
// fan out to both `toggle#select` and `export-button#tabSelected`.
//
// Exportable tabs are passed in from the server (DashboardTabs::EXPORTABLE)
// so this stays a single source of truth — see app/constants/dashboard_tabs.rb.
export default class extends Controller {
  static targets = ["container", "trigger", "csvRow", "input"]
  static values = {
    initialTab: String,
    exportableTabs: Array
  }

  connect() {
    this.applyTab(this.initialTabValue)
  }

  tabSelected(event) {
    const tab = event.currentTarget.dataset.value
    if (tab) this.applyTab(tab)
  }

  applyTab(tab) {
    const exportable = this.exportableTabsValue.includes(tab)

    if (this.hasCsvRowTarget) {
      this.csvRowTarget.classList.toggle("hidden", !exportable)
    }

    if (exportable && this.hasInputTarget) {
      this.inputTarget.value = tab
    }
  }
}
