import { Controller } from "@hotwired/stimulus"
import { renderRadar, animateRadar } from "helpers/radar_chart"

// Animated radar chart for the landing page hero.
export default class extends Controller {
  static targets = ["chart"]

  static values = {
    dimensions: { type: Object, default: {
      reporting: 2.5, attribution: 2.5, experimentation: 2.5,
      forecasting: 2.5, channels: 3.0, infrastructure: 2.0
    }}
  }

  connect() {
    this.drawn = false
    this.observer = new IntersectionObserver(entries => {
      if (entries[0].isIntersecting && !this.drawn) {
        this.drawn = true
        this.draw()
      }
    }, { threshold: 0.3 })
    this.observer.observe(this.chartTarget)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  draw() {
    renderRadar(this.chartTarget, this.dimensionsValue, { animate: true })
    animateRadar(this.chartTarget)
  }
}
