import { Controller } from "@hotwired/stimulus"

// Shows vendor details on logo click
// Usage:
//   <div data-controller="vendor-popover">
//     <img data-action="click->vendor-popover#show"
//          data-vendor-popover-name-param="Northbeam"
//          data-vendor-popover-tagline-param="ML-powered attribution"
//          data-vendor-popover-price-param="$400/mo"
//          data-vendor-popover-best-for-param="Enterprise DTC, ML believers"
//          data-vendor-popover-url-param="/articles/northbeam-alternatives">
//   </div>
export default class extends Controller {
  static targets = ["popover"]

  connect() {
    // Create popover element if it doesn't exist
    if (!this.hasPopoverTarget) {
      this.popoverElement = document.createElement("div")
      this.popoverElement.style.cssText = "display: none; position: fixed; z-index: 9999; background: white; border-radius: 12px; box-shadow: 0 25px 50px -12px rgba(0,0,0,0.25); border: 1px solid #e5e7eb; padding: 16px; width: 288px; transform: translateX(-50%);"
      this.popoverElement.setAttribute("data-vendor-popover-target", "popover")
      document.body.appendChild(this.popoverElement)
    } else {
      this.popoverElement = this.popoverTarget
    }

    // Close on outside click
    this.outsideClickHandler = (e) => {
      if (this.justOpened) return
      if (!this.popoverElement.contains(e.target) && !e.target.closest("[data-action*='vendor-popover#show']")) {
        this.hide()
      }
    }
    document.addEventListener("click", this.outsideClickHandler, true)
  }

  disconnect() {
    document.removeEventListener("click", this.outsideClickHandler)
    if (this.popoverElement && this.popoverElement.parentNode) {
      this.popoverElement.parentNode.removeChild(this.popoverElement)
    }
  }

  show(event) {
    event.preventDefault()
    event.stopImmediatePropagation()
    this.justOpened = true
    setTimeout(() => { this.justOpened = false }, 100)
    const params = event.params
    const rect = event.currentTarget.getBoundingClientRect()

    // Build popover content
    this.popoverElement.innerHTML = `
      <div class="flex items-start gap-3 mb-3">
        <img src="${event.currentTarget.src}" alt="${params.name}" class="w-12 h-12 rounded-lg object-contain bg-gray-50 p-1">
        <div class="flex-1 min-w-0">
          <div class="font-bold text-gray-900 text-sm">${params.name}</div>
          <div class="text-xs text-gray-500 truncate">${params.tagline || ''}</div>
        </div>
      </div>
      <div class="space-y-2 text-xs">
        <div class="flex justify-between">
          <span class="text-gray-500">Starting price</span>
          <span class="font-semibold text-gray-900">${params.price || 'Custom'}</span>
        </div>
        <div>
          <span class="text-gray-500">Best for:</span>
          <span class="text-gray-700 ml-1">${params.bestFor || 'Various use cases'}</span>
        </div>
      </div>
      ${params.url ? `
        <a href="${params.url}" class="mt-3 block text-center text-xs font-medium text-indigo-600 hover:text-indigo-800 py-2 bg-indigo-50 rounded-lg hover:bg-indigo-100 transition">
          ${params.url === '/signup' ? 'Start Free →' : 'View alternatives →'}
        </a>
      ` : ''}
    `

    // Position popover (fixed positioning = relative to viewport)
    let top = rect.bottom + 8
    let left = rect.left + (rect.width / 2)

    // Keep within viewport horizontally
    const popoverWidth = 288
    if (left - popoverWidth / 2 < 10) {
      left = popoverWidth / 2 + 10
    } else if (left + popoverWidth / 2 > window.innerWidth - 10) {
      left = window.innerWidth - popoverWidth / 2 - 10
    }

    // If would go below viewport, show above
    if (rect.bottom + 200 > window.innerHeight) {
      top = rect.top - 8
      this.popoverElement.style.transform = "translate(-50%, -100%)"
    } else {
      this.popoverElement.style.transform = "translate(-50%, 0)"
    }

    this.popoverElement.style.top = `${top}px`
    this.popoverElement.style.left = `${left}px`
    this.popoverElement.style.display = "block"
  }

  hide() {
    this.popoverElement.style.display = "none"
  }
}
