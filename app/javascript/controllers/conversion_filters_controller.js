import { Controller } from "@hotwired/stimulus"

// Minimal controller - just clones template and removes rows
export default class extends Controller {
  static targets = ["container", "template", "label", "empty"]

  add() {
    const index = this.containerTarget.querySelectorAll("[data-filter-row]").length
    const clone = this.templateTarget.content.cloneNode(true)

    // Update field names with correct index
    clone.querySelectorAll("[name]").forEach(el => {
      el.name = el.name.replace("INDEX", index)
    })

    if (this.hasEmptyTarget) this.emptyTarget.remove()
    this.containerTarget.appendChild(clone)
    this.updateLabel()
  }

  remove(event) {
    event.currentTarget.closest("[data-filter-row]").remove()
    this.reindex()
    this.updateLabel()
  }

  reindex() {
    this.containerTarget.querySelectorAll("[data-filter-row]").forEach((row, i) => {
      row.querySelectorAll("[name]").forEach(el => {
        el.name = el.name.replace(/\[\d+\]/, `[${i}]`)
      })
    })
  }

  updateLabel() {
    const count = this.containerTarget.querySelectorAll("[data-filter-row]").length
    this.labelTarget.textContent = count === 0 ? "No filters" : `${count} filter${count > 1 ? "s" : ""}`
  }
}
