import { Controller } from "@hotwired/stimulus"

// Custom-styled searchable combobox.
//
// Markup: a trigger button, a hidden input holding the form value, and a
// panel containing a search input + <li> options. The controller toggles
// the panel, filters the visible options as the user types, syncs the
// chosen value into the hidden input, and closes on outside click / Esc.
export default class extends Controller {
  static targets = ["trigger", "label", "panel", "input", "list", "hidden", "empty"]

  connect() {
    this.outsideClick = this.outsideClick.bind(this)
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("click", this.outsideClick)
    document.addEventListener("keydown", this.handleKeydown)
    this.placeholderText = this.labelTarget.textContent
  }

  disconnect() {
    document.removeEventListener("click", this.outsideClick)
    document.removeEventListener("keydown", this.handleKeydown)
  }

  toggle(event) {
    event.stopPropagation()
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    this.inputTarget.value = ""
    this.applyFilter("")
    requestAnimationFrame(() => this.inputTarget.focus())
  }

  close() {
    this.panelTarget.classList.add("hidden")
  }

  get isOpen() {
    return !this.panelTarget.classList.contains("hidden")
  }

  filter() {
    this.applyFilter(this.inputTarget.value.trim().toLowerCase())
  }

  applyFilter(query) {
    let visible = 0
    this.optionElements.forEach((li) => {
      const matches = li.dataset.searchLabel.toLowerCase().includes(query)
      li.hidden = !matches
      if (matches) visible += 1
    })
    if (this.hasEmptyTarget) this.emptyTarget.hidden = visible !== 0
  }

  select(event) {
    const li = event.currentTarget
    this.hiddenTarget.value = li.dataset.value
    this.labelTarget.textContent = li.dataset.searchLabel
    this.labelTarget.classList.remove("text-gray-400")
    this.labelTarget.classList.add("text-gray-900")
    this.close()
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }

  outsideClick(event) {
    if (this.isOpen && !this.element.contains(event.target)) this.close()
  }

  handleKeydown(event) {
    if (event.key === "Escape" && this.isOpen) {
      this.close()
      this.triggerTarget.focus()
    }
  }

  get optionElements() {
    return Array.from(this.listTarget.querySelectorAll("[data-searchable-select-option]"))
  }
}
