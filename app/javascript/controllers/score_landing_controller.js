import { Controller } from "@hotwired/stimulus"

// Handles landing page interactions: scroll animations, FAQ accordion, floating glow
export default class extends Controller {
  static targets = ["faqItem", "scrollGlow"]

  connect() {
    this.setupScrollObserver()
    this.setupGlow()
  }

  disconnect() {
    if (this.scrollObserver) this.scrollObserver.disconnect()
    if (this.scrollHandler) window.removeEventListener("scroll", this.scrollHandler)
    if (this.resizeHandler) window.removeEventListener("resize", this.resizeHandler)
  }

  // FAQ accordion
  toggleFaq(event) {
    const item = event.currentTarget.closest("[data-faq-item]")
    const wasOpen = item.classList.contains("open")

    this.faqItemTargets.forEach(i => i.classList.remove("open"))
    if (!wasOpen) item.classList.add("open")
  }

  // Scroll-triggered animations
  setupScrollObserver() {
    this.scrollObserver = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          const el = entry.target
          const delay = parseInt(el.dataset.delay || 0)
          setTimeout(() => el.classList.add("visible"), delay)
          this.scrollObserver.unobserve(el)
        }
      })
    }, { threshold: 0.15 })

    this.element.querySelectorAll(".chaos-card, .level-row, .fade-in").forEach(el => {
      this.scrollObserver.observe(el)
    })
  }

  // Floating glow that drifts between sections
  setupGlow() {
    if (!this.hasScrollGlowTarget) return

    this.glowWaypoints = [
      { id: "hero",  xPct: 50, yOff: -100, color: "rgba(77, 127, 255, 0.12)",  scale: 1 },
      { id: "chaos", xPct: 80, yOff: 200,  color: "rgba(167, 139, 250, 0.10)", scale: 1.1 },
      { id: "levels", xPct: 15, yOff: 200, color: "rgba(77, 127, 255, 0.10)",  scale: 1 },
      { id: "start", xPct: 50, yOff: 50,   color: "rgba(77, 127, 255, 0.14)",  scale: 1.15 }
    ]

    this.scrollHandler = () => {
      if (!this.glowTicking) {
        requestAnimationFrame(() => { this.updateGlow(); this.glowTicking = false })
        this.glowTicking = true
      }
    }
    this.resizeHandler = () => this.updateGlow()

    window.addEventListener("scroll", this.scrollHandler)
    window.addEventListener("resize", this.resizeHandler)
    this.updateGlow()
  }

  updateGlow() {
    const glow = this.scrollGlowTarget
    const scrollCenter = window.scrollY + window.innerHeight * 0.4
    const positions = this.glowWaypoints.map(wp => {
      const el = document.getElementById(wp.id)
      return { ...wp, top: el ? el.offsetTop : 0 }
    })

    let i = 0
    for (let j = positions.length - 1; j >= 0; j--) {
      if (scrollCenter >= positions[j].top) { i = j; break }
    }

    const curr = positions[i]
    const next = positions[Math.min(i + 1, positions.length - 1)]
    const range = next.top - curr.top
    const t = range > 0 ? Math.min(1, Math.max(0, (scrollCenter - curr.top) / range)) : 0

    const xPct = curr.xPct + (next.xPct - curr.xPct) * t
    const yAbs = (curr.top + curr.yOff) + ((next.top + next.yOff) - (curr.top + curr.yOff)) * t
    const scale = curr.scale + (next.scale - curr.scale) * t

    glow.style.position = "absolute"
    glow.style.left = `calc(${xPct}% - 350px)`
    glow.style.top = `${yAbs}px`
    glow.style.background = `radial-gradient(circle, ${curr.color} 0%, transparent 70%)`
    glow.style.transform = `scale(${scale})`
    glow.style.opacity = "1"
  }
}
