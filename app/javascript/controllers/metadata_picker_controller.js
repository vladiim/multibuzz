import { Controller } from "@hotwired/stimulus"

// Tag an ad-platform connection at connect time with a property key + value
// (e.g. Location: Eumundi-Noosa). User can pick a known key/value or type a new one.
//
// When a known key is picked, the value dropdown repopulates from the
// known-values map for that key. Picking "+ Add new..." swaps the select
// for a text input. The form submits both the select name and the new-input
// name; whichever has a value wins server-side.
//
// Markup contract (see select_account.html.erb):
//   data-controller="metadata-picker"
//   data-metadata-picker-known-values-value='{"location":["Sydney"], ...}'
//
//   <select data-metadata-picker-target="keySelect" data-action="change->metadata-picker#keyChanged">
//   <input  data-metadata-picker-target="keyNew" hidden>
//   <select data-metadata-picker-target="valueSelect" data-action="change->metadata-picker#valueChanged">
//   <input  data-metadata-picker-target="valueNew" hidden>
export default class extends Controller {
  static targets = ["keySelect", "keyNew", "valueSelect", "valueNew"]
  static values = { knownValues: Object }

  static NEW_SENTINEL = "__new__"

  keyChanged() {
    const key = this.keySelectTarget.value

    if (key === this.constructor.NEW_SENTINEL) {
      this.swapToNewInput(this.keySelectTarget, this.keyNewTarget)
    } else {
      this.swapToSelect(this.keySelectTarget, this.keyNewTarget)
    }

    this.repopulateValues(key)
  }

  valueChanged() {
    if (this.valueSelectTarget.value === this.constructor.NEW_SENTINEL) {
      this.swapToNewInput(this.valueSelectTarget, this.valueNewTarget)
    } else {
      this.swapToSelect(this.valueSelectTarget, this.valueNewTarget)
    }
  }

  swapToNewInput(select, input) {
    select.hidden = true
    select.disabled = true
    input.hidden = false
    input.disabled = false
    input.focus()
  }

  swapToSelect(select, input) {
    select.hidden = false
    select.disabled = false
    input.hidden = true
    input.disabled = true
    input.value = ""
  }

  repopulateValues(key) {
    const values = (this.knownValuesValue || {})[key] || []
    const select = this.valueSelectTarget

    select.innerHTML = ""
    select.appendChild(this.option("", "— Choose value —"))
    values.forEach((v) => select.appendChild(this.option(v, v)))
    select.appendChild(this.option(this.constructor.NEW_SENTINEL, "+ Add new value..."))

    this.swapToSelect(select, this.valueNewTarget)
  }

  option(value, label) {
    const opt = document.createElement("option")
    opt.value = value
    opt.textContent = label
    return opt
  }
}
