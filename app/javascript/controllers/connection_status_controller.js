import { Controller } from "@hotwired/stimulus"

// Monitors Turbo Streams WebSocket connection status
//
// Usage:
//   <div data-controller="connection-status">
//     <span data-connection-status-target="dot"></span>
//     <span data-connection-status-target="text"></span>
//   </div>
//
export default class extends Controller {
  static targets = ["dot", "text"]

  connect() {
    this.boundOnOpen = () => this.updateStatus(true)
    this.boundOnClose = () => this.updateStatus(false)

    // Initial check
    this.checkConnection()

    // Monitor ActionCable connection events
    const consumer = this.getConsumer()
    if (consumer?.connection) {
      consumer.connection.events.open.add(this.boundOnOpen)
      consumer.connection.events.close.add(this.boundOnClose)
    }

    // Fallback: check periodically
    this.interval = setInterval(() => this.checkConnection(), 5000)
  }

  disconnect() {
    if (this.interval) clearInterval(this.interval)

    const consumer = this.getConsumer()
    if (consumer?.connection) {
      consumer.connection.events.open.delete(this.boundOnOpen)
      consumer.connection.events.close.delete(this.boundOnClose)
    }
  }

  getConsumer() {
    return window.Turbo?.cable?.consumer
  }

  checkConnection() {
    const consumer = this.getConsumer()
    const isConnected = consumer?.connection?.isOpen() ?? false
    this.updateStatus(isConnected)
  }

  updateStatus(isConnected) {
    if (this.hasDotTarget) {
      this.dotTarget.classList.toggle("bg-green-500", isConnected)
      this.dotTarget.classList.toggle("bg-yellow-500", !isConnected)
    }

    if (this.hasTextTarget) {
      this.textTarget.textContent = isConnected ? "Live" : "Refresh required"
    }
  }
}
