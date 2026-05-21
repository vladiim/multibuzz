import { Controller } from "@hotwired/stimulus"

// Pairs a text input with a <select> so users can type to filter options.
// Hidden options stay in the DOM (so form submission keeps the value) but
// are display:none and not in the visible option list.
export default class extends Controller {
  static targets = ["input", "select"]

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()
    const options = Array.from(this.selectTarget.options)

    let firstMatch = null
    options.forEach((option) => {
      if (!option.value) {
        option.hidden = false
        return
      }

      const matches = option.text.toLowerCase().includes(query)
      option.hidden = !matches
      if (matches && !firstMatch) firstMatch = option
    })

    if (firstMatch && query.length > 0) this.selectTarget.value = firstMatch.value
  }
}
