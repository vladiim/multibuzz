import { Controller } from "@hotwired/stimulus"

// Simple modal controller
// Usage:
//   <button data-controller="modal" data-action="click->modal#open" data-modal-target-value="my-modal">Open</button>
//   <div id="my-modal" class="hidden" data-controller="modal">
//     <div data-action="click->modal#close">Backdrop</div>
//     <div>Modal content</div>
//   </div>
//
export default class extends Controller {
  static values = { target: String }

  open() {
    const modal = document.getElementById(this.targetValue)
    if (modal) {
      modal.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
    }
  }

  close() {
    this.element.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  closeWithEscape(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  connect() {
    if (this.element.id) {
      this.boundCloseWithEscape = this.closeWithEscape.bind(this)
      document.addEventListener("keydown", this.boundCloseWithEscape)
    }
  }

  disconnect() {
    if (this.boundCloseWithEscape) {
      document.removeEventListener("keydown", this.boundCloseWithEscape)
    }
  }
}
