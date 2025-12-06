import { Controller } from "@hotwired/stimulus"

// Auto-submit form on input change
//
// Usage:
//   <form data-controller="auto-submit">
//     <input data-action="change->auto-submit#submit">
//   </form>
//
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
