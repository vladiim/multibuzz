import { Controller } from "@hotwired/stimulus"

// Generic toggle controller - supports simple show/hide AND tabbed switching
//
// Simple toggle usage:
//   <div data-controller="toggle">
//     <button data-action="toggle#toggle">Toggle</button>
//     <div data-toggle-target="content">Content</div>
//   </div>
//
// Tabbed switching usage:
//   <div data-controller="toggle" data-toggle-default-value="ruby" data-toggle-persist-value="docs_language">
//     <button data-action="toggle#switch" data-toggle-target="trigger" data-value="ruby">Ruby</button>
//     <button data-action="toggle#switch" data-toggle-target="trigger" data-value="python">Python</button>
//     <div data-toggle-target="content" data-value="ruby">Ruby code</div>
//     <div data-toggle-target="content" data-value="python">Python code</div>
//   </div>
//
// Global sync: All toggle controllers with the same persist key sync together.
// When you select "Python" in one code block, all others switch to Python too.
//
export default class extends Controller {
  static targets = ["content", "trigger", "input", "filters"]
  static classes = ["hidden", "active", "inactive", "activeTab", "inactiveTab"]
  static values = {
    default: String,
    persist: String,  // localStorage key (optional)
    urlParam: String, // URL search param to sync (optional)
    closeOnClickOutside: Boolean
  }

  connect() {
    // If we have triggers (tabs), initialize tabbed mode
    if (this.hasTriggerTarget) {
      const initialValue = this.loadPreference() || this.defaultValue
      if (initialValue) {
        this.switchTo(initialValue)
      }
    }

    // Set up click-outside listener if enabled
    if (this.closeOnClickOutsideValue) {
      this.boundCloseOnClickOutside = this.closeOnClickOutside.bind(this)
      document.addEventListener("click", this.boundCloseOnClickOutside)
    }

    // Listen for global sync events (same persist key = sync together)
    if (this.hasPersistValue) {
      this.boundHandleGlobalSync = this.handleGlobalSync.bind(this)
      document.addEventListener("toggle:sync", this.boundHandleGlobalSync)
    }
  }

  disconnect() {
    if (this.boundCloseOnClickOutside) {
      document.removeEventListener("click", this.boundCloseOnClickOutside)
    }
    if (this.boundHandleGlobalSync) {
      document.removeEventListener("toggle:sync", this.boundHandleGlobalSync)
    }
  }

  // Handle sync events from other toggle controllers
  handleGlobalSync(event) {
    const { persistKey, value, source } = event.detail
    // Only sync if same persist key and not the source element
    if (persistKey === this.persistValue && source !== this.element) {
      // Only switch if this controller has that value available
      if (this.hasValueOption(value)) {
        this.switchTo(value)
      }
    }
  }

  // Check if this toggle has a specific value option
  hasValueOption(value) {
    return this.triggerTargets.some(trigger => trigger.dataset.value === value)
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hide()
    }
  }

  // Simple toggle (show/hide all content)
  toggle() {
    this.contentTargets.forEach(target => {
      target.classList.toggle(this.hiddenClass)
    })
  }

  show() {
    this.contentTargets.forEach(target => {
      target.classList.remove(this.hiddenClass)
    })
  }

  hide() {
    this.contentTargets.forEach(target => {
      target.classList.add(this.hiddenClass)
    })
  }

  // Toggle filters panel specifically
  toggleFilters() {
    if (this.hasFiltersTarget) {
      this.filtersTarget.classList.toggle(this.hiddenClass)
    }
  }

  // Handle date range select change - show/hide custom date inputs
  handleDateRange(event) {
    const isCustom = event.target.value === "custom"
    this.contentTargets.forEach(target => {
      target.classList.toggle(this.hiddenClass, !isCustom)
    })
  }

  // Tab switching
  select(event) {
    const value = event.currentTarget.dataset.value
    this.switchTo(value)
    this.savePreference(value)
    this.updateUrlParam(value)
    this.broadcastSync(value)
  }

  // Broadcast selection to all other toggle controllers with same persist key
  broadcastSync(value) {
    if (!this.hasPersistValue) return

    document.dispatchEvent(new CustomEvent("toggle:sync", {
      detail: {
        persistKey: this.persistValue,
        value: value,
        source: this.element
      }
    }))
  }

  switchTo(value) {
    // Update triggers (tab buttons)
    this.triggerTargets.forEach(trigger => {
      const isActive = trigger.dataset.value === value

      if (isActive) {
        trigger.classList.add('active')
        if (this.hasActiveClass) {
          this.activeClasses.forEach(cls => trigger.classList.add(cls))
        }
        if (this.hasInactiveClass) {
          this.inactiveClasses.forEach(cls => trigger.classList.remove(cls))
        }
      } else {
        trigger.classList.remove('active')
        if (this.hasActiveClass) {
          this.activeClasses.forEach(cls => trigger.classList.remove(cls))
        }
        if (this.hasInactiveClass) {
          this.inactiveClasses.forEach(cls => trigger.classList.add(cls))
        }
      }
    })

    // Update content panels
    this.contentTargets.forEach(content => {
      const isActive = content.dataset.value === value

      if (isActive) {
        content.classList.add('active')
        content.classList.remove(this.hiddenClass)
        content.hidden = false
      } else {
        content.classList.remove('active')
        content.classList.add(this.hiddenClass)
        content.hidden = true
      }
    })

    // Sync value to hidden input if present
    if (this.hasInputTarget) {
      this.inputTarget.value = value
    }
  }

  loadPreference() {
    if (!this.hasPersistValue) return null
    try {
      return localStorage.getItem(this.persistValue)
    } catch {
      return null
    }
  }

  savePreference(value) {
    if (!this.hasPersistValue) return
    try {
      localStorage.setItem(this.persistValue, value)
    } catch {
      // Silently fail if localStorage unavailable
    }
  }

  updateUrlParam(value) {
    if (!this.hasUrlParamValue) return

    const param = this.urlParamValue
    const url = new URL(window.location.href)
    url.searchParams.set(param, value)
    history.replaceState(history.state, "", url.toString())

    // Sync hidden inputs in any already-loaded forms
    this.element.querySelectorAll(`input[type="hidden"][name="${param}"]`).forEach(input => {
      input.value = value
    })

    // Update turbo frame src attributes so lazy-loaded frames pick up the new param
    this.element.querySelectorAll("turbo-frame[src]").forEach(frame => {
      const frameUrl = new URL(frame.src, window.location.origin)
      frameUrl.searchParams.set(param, value)
      frame.src = frameUrl.toString()
    })
  }

  get hiddenClass() {
    return this.hasHiddenClass ? this.hiddenClasses[0] : "hidden"
  }
}
