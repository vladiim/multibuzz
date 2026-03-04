import { Controller } from "@hotwired/stimulus"

// Filters content panels by a <select> value.
//
// Usage:
//   <div data-controller="filter">
//     <select data-action="filter#change" data-filter-target="select">
//       <option value="linear">Linear</option>
//     </select>
//     <div data-filter-target="content" data-value="linear">...</div>
//     <div data-filter-target="content" data-value="first_touch">...</div>
//   </div>
//
export default class extends Controller {
  static targets = ["select", "content"]

  connect() {
    this.change()
  }

  change() {
    const selected = this.selectTarget.value

    this.contentTargets.forEach(el => {
      el.hidden = el.dataset.value !== selected
    })
  }
}
