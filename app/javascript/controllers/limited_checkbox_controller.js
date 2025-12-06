import { Controller } from "@hotwired/stimulus"

// Generic controller for limiting checkbox selections
// Usage:
//   data-controller="limited-checkbox"
//   data-limited-checkbox-max-value="2"
//   data-limited-checkbox-singular-value="model"
//   data-limited-checkbox-plural-value="models"
export default class extends Controller {
  static targets = ["checkbox", "label"]
  static values = {
    max: { type: Number, default: 2 },
    singular: { type: String, default: "item" },
    plural: { type: String, default: "items" }
  }

  connect() {
    this.updateState()
  }

  change() {
    this.updateState()
  }

  updateState() {
    const checked = this.checkboxTargets.filter(cb => cb.checked)
    const atMax = checked.length >= this.maxValue

    this.checkboxTargets.forEach(cb => {
      const label = cb.closest("label")
      const shouldDisable = !cb.checked && atMax

      cb.disabled = shouldDisable
      label?.classList.toggle("opacity-50", shouldDisable)
      label?.classList.toggle("cursor-not-allowed", shouldDisable)
      label?.classList.toggle("cursor-pointer", !shouldDisable)
    })

    this.updateLabel(checked.length)
  }

  updateLabel(count) {
    if (!this.hasLabelTarget) return

    const noun = count === 1 ? this.singularValue : this.pluralValue
    this.labelTarget.textContent = count === 0 ? `Select ${this.pluralValue}` : `${count} ${noun}`
  }
}
