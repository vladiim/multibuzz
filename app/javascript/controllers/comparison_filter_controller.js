import { Controller } from "@hotwired/stimulus"

// Filterable comparison table for attribution tools
// Usage:
//   <div data-controller="comparison-filter">
//     <select data-comparison-filter-target="preset" data-action="change->comparison-filter#filter">
//     <div data-comparison-filter-target="priceFilter" data-price="500" data-action="click->comparison-filter#togglePrice">
//     <input type="checkbox" data-comparison-filter-target="feature" data-feature="server_side" data-action="change->comparison-filter#filter">
//     <tr data-comparison-filter-target="row" data-price="400" data-categories="dtc,b2b" data-features="...">
//   </div>
export default class extends Controller {
  static targets = ["row", "preset", "priceFilter", "categoryFilter", "feature", "setupTimeFilter", "count", "noResults"]

  connect() {
    this.filter()
  }

  filter() {
    const activeFilters = this.getActiveFilters()
    let visibleCount = 0

    this.rowTargets.forEach(row => {
      const visible = this.matchesFilters(row, activeFilters)
      row.style.display = visible ? "" : "none"
      if (visible) visibleCount++
    })

    // Update count display
    if (this.hasCountTarget) {
      this.countTarget.textContent = `${visibleCount} tool${visibleCount !== 1 ? 's' : ''}`
    }

    // Show/hide no results message
    if (this.hasNoResultsTarget) {
      this.noResultsTarget.style.display = visibleCount === 0 ? "" : "none"
    }
  }

  getActiveFilters() {
    const filters = {
      preset: null,
      priceMax: null,
      setupTimeMax: null,
      categories: [],
      features: []
    }

    // Preset filter (alternatives for X)
    if (this.hasPresetTarget && this.presetTarget.value) {
      filters.preset = this.presetTarget.value
    }

    // Price filter (active price button)
    this.priceFilterTargets.forEach(el => {
      if (el.classList.contains("active")) {
        filters.priceMax = parseInt(el.dataset.priceMax) || null
      }
    })

    // Setup time filter (active setup time button)
    this.setupTimeFilterTargets.forEach(el => {
      if (el.classList.contains("active")) {
        filters.setupTimeMax = parseInt(el.dataset.setupMax) || null
      }
    })

    // Category filters
    this.categoryFilterTargets.forEach(el => {
      if (el.checked || el.classList.contains("active")) {
        filters.categories.push(el.dataset.category)
      }
    })

    // Feature filters
    this.featureTargets.forEach(el => {
      if (el.checked || el.classList.contains("active")) {
        filters.features.push(el.dataset.feature)
      }
    })

    return filters
  }

  matchesFilters(row, filters) {
    // Preset filter - exclude the tool we're finding alternatives for
    if (filters.preset && row.dataset.slug === filters.preset) {
      return false
    }

    // Price filter
    if (filters.priceMax !== null) {
      const price = parseInt(row.dataset.price) || 0
      // Free tier check
      if (filters.priceMax === 0 && row.dataset.hasFreeTier !== "true") {
        return false
      }
      // Price range check
      if (filters.priceMax > 0 && price > filters.priceMax) {
        return false
      }
    }

    // Setup time filter
    if (filters.setupTimeMax !== null) {
      const setupHours = parseInt(row.dataset.setupHours) || 9999
      if (setupHours > filters.setupTimeMax) {
        return false
      }
    }

    // Category filter (OR logic - match any selected category)
    // Rows can have multiple categories (comma-separated)
    if (filters.categories.length > 0) {
      const rowCategories = (row.dataset.categories || "").split(",")
      const hasMatch = filters.categories.some(cat => rowCategories.includes(cat))
      if (!hasMatch) {
        return false
      }
    }

    // Feature filter (AND logic - must have all selected features)
    if (filters.features.length > 0) {
      const rowFeatures = (row.dataset.features || "").split(",")
      for (const feature of filters.features) {
        if (!rowFeatures.includes(feature)) {
          return false
        }
      }
    }

    return true
  }

  togglePrice(event) {
    // Remove active from all price filters
    this.priceFilterTargets.forEach(el => {
      el.classList.remove("active", "bg-indigo-600", "text-white")
      el.classList.add("bg-gray-100", "text-gray-700")
    })

    // Add active to clicked one (unless clicking the same one to deselect)
    const target = event.currentTarget
    if (!target.classList.contains("active")) {
      target.classList.add("active", "bg-indigo-600", "text-white")
      target.classList.remove("bg-gray-100", "text-gray-700")
    }

    this.filter()
  }

  toggleCategory(event) {
    event.currentTarget.classList.toggle("active")
    event.currentTarget.classList.toggle("bg-indigo-100")
    event.currentTarget.classList.toggle("text-indigo-700")
    event.currentTarget.classList.toggle("bg-gray-100")
    event.currentTarget.classList.toggle("text-gray-600")
    this.filter()
  }

  toggleSetupTime(event) {
    // Remove active from all setup time filters
    this.setupTimeFilterTargets.forEach(el => {
      el.classList.remove("active", "bg-amber-600", "text-white")
      el.classList.add("bg-gray-100", "text-gray-600")
    })

    // Add active to clicked one (unless clicking the same one to deselect)
    const target = event.currentTarget
    if (!target.classList.contains("active")) {
      target.classList.add("active", "bg-amber-600", "text-white")
      target.classList.remove("bg-gray-100", "text-gray-600")
    }

    this.filter()
  }

  toggleFeature(event) {
    event.currentTarget.classList.toggle("active")
    event.currentTarget.classList.toggle("bg-emerald-100")
    event.currentTarget.classList.toggle("text-emerald-700")
    event.currentTarget.classList.toggle("bg-gray-100")
    event.currentTarget.classList.toggle("text-gray-600")
    this.filter()
  }

  clearFilters() {
    // Reset preset
    if (this.hasPresetTarget) {
      this.presetTarget.value = ""
    }

    // Reset price filters
    this.priceFilterTargets.forEach(el => {
      el.classList.remove("active", "bg-indigo-600", "text-white")
      el.classList.add("bg-gray-100", "text-gray-700")
    })

    // Reset setup time filters
    this.setupTimeFilterTargets.forEach(el => {
      el.classList.remove("active", "bg-amber-600", "text-white")
      el.classList.add("bg-gray-100", "text-gray-600")
    })

    // Reset category filters
    this.categoryFilterTargets.forEach(el => {
      el.classList.remove("active", "bg-indigo-100", "text-indigo-700")
      el.classList.add("bg-gray-100", "text-gray-600")
    })

    // Reset feature filters
    this.featureTargets.forEach(el => {
      el.classList.remove("active", "bg-emerald-100", "text-emerald-700")
      el.classList.add("bg-gray-100", "text-gray-600")
      if (el.type === "checkbox") el.checked = false
    })

    this.filter()
  }
}
