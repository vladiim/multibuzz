import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["spinner"]

  submit() {
    this.spinnerTarget.classList.remove("hidden")
  }
}
