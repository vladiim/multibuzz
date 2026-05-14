import { Controller } from "@hotwired/stimulus"

// Binds the dashboard's "Download CSV" button to the active tab.
//
// - Hides the dropdown trigger when the active tab is not exportable (Events).
// - Rewrites the hidden export_type input to match the active tab so the
//   submitted form posts the right export_type to /dashboard/export.
//
// Lives on the same element as the outer toggle controller; tab buttons
// fan out to both `toggle#select` and `export-button#tabSelected`.
//
// Exportable tabs are passed in from the server (DashboardTabs::EXPORTABLE)
// so this stays a single source of truth — see app/constants/dashboard_tabs.rb.
export default class extends Controller {
  static targets = ["container", "trigger", "input"]
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

    if (this.hasTriggerTarget) {
      this.triggerTarget.classList.toggle("hidden", !exportable)
    }

    if (exportable && this.hasInputTarget) {
      this.inputTarget.value = tab
    }
  }
}
