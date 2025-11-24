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
export default class extends Controller {
  static targets = ["content", "trigger"]
  static classes = ["hidden", "active", "inactive"]
  static values = {
    default: String,
    persist: String  // localStorage key (optional)
  }

  connect() {
    // If we have triggers (tabs), initialize tabbed mode
    if (this.hasTriggerTarget) {
      const initialValue = this.loadPreference() || this.defaultValue
      if (initialValue) {
        this.switchTo(initialValue)
      }
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

  // Tab switching
  switch(event) {
    const value = event.currentTarget.dataset.value
    this.switchTo(value)
    this.savePreference(value)
  }

  switchTo(value) {
    // Update triggers (tab buttons)
    this.triggerTargets.forEach(trigger => {
      const isActive = trigger.dataset.value === value
      this.updateTriggerClasses(trigger, isActive)
    })

    // Update content panels
    this.contentTargets.forEach(content => {
      const isActive = content.dataset.value === value

      if (isActive) {
        content.classList.remove(this.hiddenClass)
        content.hidden = false
      } else {
        content.classList.add(this.hiddenClass)
        content.hidden = true
      }
    })
  }

  updateTriggerClasses(element, isActive) {
    if (this.hasActiveClass && this.hasInactiveClass) {
      if (isActive) {
        this.inactiveClasses.forEach(cls => element.classList.remove(cls))
        this.activeClasses.forEach(cls => element.classList.add(cls))
      } else {
        this.activeClasses.forEach(cls => element.classList.remove(cls))
        this.inactiveClasses.forEach(cls => element.classList.add(cls))
      }
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

  get hiddenClass() {
    return this.hasHiddenClass ? this.hiddenClasses[0] : "hidden"
  }
}
