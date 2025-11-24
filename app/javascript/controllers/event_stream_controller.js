import { Controller } from "@hotwired/stimulus"

// Event stream animation - simulates real-time event debugging
export default class extends Controller {
  static targets = ["log"]

  events = [
    { type: "page_view", channel: "paid_search", utm_source: "google", status: "✓", color: "text-green-400" },
    { type: "signup", channel: "organic_social", utm_source: "twitter", status: "✓", color: "text-green-400" },
    { type: "page_view", channel: "email", utm_source: "campaign_123", status: "✓", color: "text-green-400" },
    { type: "add_to_cart", channel: "paid_social", utm_source: "facebook", status: "✓", color: "text-green-400" },
    { type: "page_view", channel: "direct", utm_source: null, status: "✓", color: "text-green-400" },
    { type: "purchase", channel: "email", utm_source: "campaign_123", status: "✓", color: "text-green-400" },
    { type: "page_view", channel: "referral", utm_source: "producthunt", status: "✓", color: "text-green-400" },
    { type: "invalid_event", channel: null, utm_source: null, status: "✗", color: "text-red-400" }
  ]

  connect() {
    this.eventIndex = 0
    this.startStreaming()
  }

  disconnect() {
    if (this.intervalId) {
      clearInterval(this.intervalId)
    }
  }

  startStreaming() {
    // Add initial events immediately
    this.addEvent()
    this.addEvent()
    this.addEvent()

    // Then continue streaming
    this.intervalId = setInterval(() => {
      this.addEvent()
    }, 2000)
  }

  addEvent() {
    const event = this.events[this.eventIndex % this.events.length]
    this.eventIndex++

    const timestamp = new Date().toISOString().substring(11, 23)
    const utmPart = event.utm_source
      ? `utm_source=${event.utm_source}`
      : "no_utm"
    const channelPart = event.channel || "unknown"

    const eventLine = document.createElement("div")
    eventLine.className = "font-mono text-xs opacity-0 transition-opacity duration-300"
    eventLine.innerHTML = `
      <span class="text-gray-500">[${timestamp}]</span>
      <span class="${event.color}">${event.status}</span>
      <span class="text-blue-400">${event.type}</span>
      <span class="text-gray-500">→</span>
      <span class="text-purple-400">${channelPart}</span>
      <span class="text-gray-600">${utmPart}</span>
    `

    this.logTarget.appendChild(eventLine)

    // Fade in
    setTimeout(() => {
      eventLine.style.opacity = "1"
    }, 10)

    // Keep only last 10 events
    while (this.logTarget.children.length > 10) {
      this.logTarget.removeChild(this.logTarget.firstChild)
    }

    // Auto-scroll
    this.logTarget.scrollTop = this.logTarget.scrollHeight
  }
}
