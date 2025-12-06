import { Controller } from "@hotwired/stimulus"

// Event panel slide-out controller for live events debugger
//
// Usage:
//   <div data-controller="event-panel">
//     <div data-event-json="..." data-action="click->event-panel#open">Event card</div>
//     <div id="event-panel">Panel content</div>
//     <div id="event-panel-backdrop" data-action="click->event-panel#close"></div>
//   </div>
//
export default class extends Controller {
  static targets = [
    "content",
    "eventId",
    "eventType",
    "occurredAt",
    "channel",
    "sessionId",
    "visitorId",
    "properties",
    "json",
    "jsonToggle"
  ]

  connect() {
    this.panel = document.getElementById("event-panel")
    this.backdrop = document.getElementById("event-panel-backdrop")
    this.boundHandleKeydown = this.handleKeydown.bind(this)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKeydown)
  }

  open(event) {
    const eventData = JSON.parse(event.currentTarget.dataset.eventJson)
    this.populatePanel(eventData)
    this.showPanel()
    document.addEventListener("keydown", this.boundHandleKeydown)
  }

  close() {
    this.hidePanel()
    document.removeEventListener("keydown", this.boundHandleKeydown)
  }

  toggleJson() {
    if (this.hasJsonTarget) {
      this.jsonTarget.classList.toggle("hidden")
      if (this.hasJsonToggleTarget) {
        this.jsonToggleTarget.classList.toggle("rotate-180")
      }
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  populatePanel(data) {
    if (this.hasEventIdTarget) {
      this.eventIdTarget.textContent = data.id
    }
    if (this.hasEventTypeTarget) {
      this.eventTypeTarget.textContent = data.event_type
    }
    if (this.hasOccurredAtTarget) {
      this.occurredAtTarget.textContent = data.occurred_at_formatted
    }
    if (this.hasChannelTarget) {
      this.channelTarget.textContent = data.channel || "—"
    }
    if (this.hasSessionIdTarget) {
      this.sessionIdTarget.textContent = data.session_id || "—"
    }
    if (this.hasVisitorIdTarget) {
      this.visitorIdTarget.textContent = data.visitor_id || "—"
    }
    if (this.hasPropertiesTarget) {
      this.propertiesTarget.innerHTML = this.formatProperties(data.properties)
    }
    if (this.hasJsonTarget) {
      const pre = this.jsonTarget.querySelector("pre")
      if (pre) {
        pre.textContent = JSON.stringify(data, null, 2)
      }
      // Reset to collapsed state
      this.jsonTarget.classList.add("hidden")
      if (this.hasJsonToggleTarget) {
        this.jsonToggleTarget.classList.remove("rotate-180")
      }
    }
  }

  formatProperties(properties) {
    if (!properties || Object.keys(properties).length === 0) {
      return '<p class="text-sm text-gray-500">No properties</p>'
    }

    return Object.entries(properties)
      .map(([key, value]) => `
        <div class="flex justify-between text-sm">
          <span class="text-gray-500">${this.escapeHtml(key)}</span>
          <span class="text-gray-900 font-mono text-xs truncate max-w-[200px]" title="${this.escapeHtml(String(value))}">
            ${this.escapeHtml(String(value))}
          </span>
        </div>
      `)
      .join("")
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  showPanel() {
    if (this.panel) {
      this.panel.classList.remove("translate-x-full")
    }
    if (this.backdrop) {
      this.backdrop.classList.remove("hidden")
    }
  }

  hidePanel() {
    if (this.panel) {
      this.panel.classList.add("translate-x-full")
    }
    if (this.backdrop) {
      this.backdrop.classList.add("hidden")
    }
  }
}
