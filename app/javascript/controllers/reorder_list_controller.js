import { Controller } from "@hotwired/stimulus"

// Generic FLIP animation controller for reordering lists
//
// Usage:
//   <div data-controller="reorder-list" data-reorder-list-view-value="view-a">
//     <button data-action="reorder-list#switchTo" data-view="view-a">View A</button>
//     <button data-action="reorder-list#switchTo" data-view="view-b">View B</button>
//
//     <div data-reorder-list-target="container">
//       <div data-reorder-list-target="item" data-order-view-a="1" data-order-view-b="3">
//         <span data-show="view-a">Content A</span>
//         <span data-show="view-b">Content B</span>
//       </div>
//     </div>
//   </div>
//
// Features:
//   - FLIP animation when items reorder
//   - data-order-{view} defines sort order per view
//   - data-show="{view}" shows/hides elements per view
//   - data-class-{view}="classes" adds classes when view is active
//   - data-reorder-list-target="trigger" auto-toggles "active" class on buttons
//
export default class extends Controller {
  static targets = ["container", "item", "trigger"]
  static values = {
    view: String,
    duration: { type: Number, default: 400 }
  }

  connect() {
    if (this.viewValue) {
      this.applyView(this.viewValue, false)
    }
  }

  switchTo(event) {
    const view = event.currentTarget.dataset.view
    if (view === this.viewValue) return

    this.applyView(view, true)
    this.viewValue = view
  }

  applyView(view, animate = true) {
    this.updateTriggers(view)
    this.updateVisibility(view)
    this.updateClasses(view)

    if (animate && this.hasContainerTarget) {
      this.animateReorder(view)
    } else {
      this.reorderInstant(view)
    }
  }

  updateTriggers(view) {
    this.triggerTargets.forEach(trigger => {
      trigger.classList.toggle("active", trigger.dataset.view === view)
    })
  }

  updateVisibility(view) {
    // Handle data-show="{view}" elements
    this.element.querySelectorAll("[data-show]").forEach(el => {
      const showViews = el.dataset.show.split(" ")
      el.classList.toggle("hidden", !showViews.includes(view))
    })

    // Handle data-hide="{view}" elements
    this.element.querySelectorAll("[data-hide]").forEach(el => {
      const hideViews = el.dataset.hide.split(" ")
      el.classList.toggle("hidden", hideViews.includes(view))
    })
  }

  updateClasses(view) {
    // Handle data-class-{view}="classes" on items
    this.itemTargets.forEach(item => {
      // Remove all view-specific classes first
      Object.keys(item.dataset).forEach(key => {
        if (key.startsWith("class") && key !== "class") {
          const classes = item.dataset[key].split(" ").filter(Boolean)
          classes.forEach(cls => item.classList.remove(cls))
        }
      })

      // Add classes for current view
      const viewKey = `class${this.camelCase(view)}`
      if (item.dataset[viewKey]) {
        const classes = item.dataset[viewKey].split(" ").filter(Boolean)
        classes.forEach(cls => item.classList.add(cls))
      }
    })
  }

  animateReorder(view) {
    const items = this.itemTargets
    const container = this.hasContainerTarget ? this.containerTarget : items[0]?.parentElement
    if (!container || items.length === 0) return

    // FLIP Step 1: First - record current positions
    const firstPositions = new Map()
    items.forEach(item => {
      const rect = item.getBoundingClientRect()
      firstPositions.set(item, { top: rect.top, left: rect.left })
    })

    // Reorder DOM
    this.reorderItems(view, container)

    // Force layout recalculation
    container.offsetHeight

    // FLIP Step 2: Last - get new positions and calculate deltas
    // FLIP Step 3: Invert - apply inverse transforms
    items.forEach(item => {
      const first = firstPositions.get(item)
      const last = item.getBoundingClientRect()

      const deltaX = first.left - last.left
      const deltaY = first.top - last.top

      if (deltaX !== 0 || deltaY !== 0) {
        item.style.transform = `translate(${deltaX}px, ${deltaY}px)`
        item.style.transition = "none"
      }
    })

    // Force another layout
    container.offsetHeight

    // FLIP Step 4: Play - animate to final position
    items.forEach(item => {
      item.style.transition = `transform ${this.durationValue}ms cubic-bezier(0.4, 0, 0.2, 1)`
      item.style.transform = ""
    })

    // Clean up after animation
    setTimeout(() => {
      items.forEach(item => {
        item.style.transition = ""
        item.style.transform = ""
      })
    }, this.durationValue)
  }

  reorderInstant(view) {
    const container = this.hasContainerTarget ? this.containerTarget : this.itemTargets[0]?.parentElement
    if (container) {
      this.reorderItems(view, container)
    }
  }

  reorderItems(view, container) {
    const orderKey = `order${this.camelCase(view)}`

    const sortedItems = [...this.itemTargets].sort((a, b) => {
      const orderA = parseInt(a.dataset[orderKey]) || 999
      const orderB = parseInt(b.dataset[orderKey]) || 999
      return orderA - orderB
    })

    sortedItems.forEach(item => container.appendChild(item))
  }

  // Convert "view-name" to "ViewName" for dataset access
  camelCase(str) {
    return str.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())
      .replace(/^([a-z])/, (_, letter) => letter.toUpperCase())
  }
}
