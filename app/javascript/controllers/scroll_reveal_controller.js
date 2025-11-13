import { Controller } from "@hotwired/stimulus"

// Reveals elements as they scroll into view
export default class extends Controller {
  connect() {
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-visible')
            // Optionally unobserve after revealing
            // this.observer.unobserve(entry.target)
          }
        })
      },
      {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
      }
    )

    this.observer.observe(this.element)
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }
}
