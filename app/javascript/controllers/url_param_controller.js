import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Generic controller for updating URL params and navigating
// Usage:
//   data-controller="url-param"
//   data-url-param-name-value="funnel"
//   data-action="change->url-param#update"
export default class extends Controller {
  static values = { name: String }

  update(event) {
    const url = new URL(window.location.href)
    const value = event.target.value

    value ? url.searchParams.set(this.nameValue, value) : url.searchParams.delete(this.nameValue)

    Turbo.visit(url.toString())
  }
}
