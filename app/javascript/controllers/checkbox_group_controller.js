import { Controller } from "@hotwired/stimulus"

// Generic controller for checkbox groups with select all/none functionality
// Usage:
//   <div data-controller="checkbox-group"
//        data-checkbox-group-all-label-value="All Channels"
//        data-checkbox-group-none-label-value="None selected"
//        data-checkbox-group-selected-label-value="{count} selected">
//     <span data-checkbox-group-target="label">All Channels</span>
//     <button data-action="checkbox-group#selectAll">All</button>
//     <button data-action="checkbox-group#selectNone">None</button>
//     <input type="checkbox" data-checkbox-group-target="checkbox" data-action="change->checkbox-group#change">
//   </div>
export default class extends Controller {
  static targets = ["checkbox", "label"]
  static values = {
    allLabel: { type: String, default: "All selected" },
    noneLabel: { type: String, default: "None selected" },
    selectedLabel: { type: String, default: "{count} selected" }
  }

  connect() {
    this.updateLabel()
  }

  selectAll() {
    this.checkboxTargets.forEach(cb => {
      cb.checked = true
      cb.disabled = false
    })
    this.updateLabel()
  }

  selectNone() {
    this.checkboxTargets.forEach(cb => {
      cb.checked = false
      cb.disabled = false
    })
    this.updateLabel()
  }

  change() {
    this.updateLabel()
  }

  updateLabel() {
    if (!this.hasLabelTarget) return

    const checked = this.checkboxTargets.filter(cb => cb.checked).length
    const total = this.checkboxTargets.length

    if (checked === 0) {
      this.labelTarget.textContent = this.noneLabelValue
    } else if (checked === total) {
      this.labelTarget.textContent = this.allLabelValue
    } else {
      this.labelTarget.textContent = this.selectedLabelValue.replace("{count}", checked)
    }
  }

  get checkedCount() {
    return this.checkboxTargets.filter(cb => cb.checked).length
  }
}
