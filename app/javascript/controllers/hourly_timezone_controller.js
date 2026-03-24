import { Controller } from "@hotwired/stimulus"

// Shifts hourly spend bars by timezone offset (client-side, no server round-trip)
//
// Usage:
//   <div data-controller="hourly-timezone"
//        data-hourly-timezone-spend-value='{"0":80,"1":60,...,"23":120}'>
//     <select data-hourly-timezone-target="select" data-action="change->hourly-timezone#shift">
//     <div data-hourly-timezone-target="chart">
//     <div data-hourly-timezone-target="bar" data-hour="0">
//
export default class extends Controller {
  static targets = ["select", "chart", "bar"]
  static values = { spend: Object }

  shift() {
    const offset = parseInt(this.selectTarget.value) || 0
    const spend = this.spendValue
    const shifted = this.shiftSpend(spend, offset)
    const max = Math.max(...Object.values(shifted), 1)

    this.barTargets.forEach(bar => {
      const hour = parseInt(bar.dataset.hour)
      const value = shifted[hour] || 0
      const pct = Math.max(Math.round((value / max) * 100), 2)
      bar.style.height = `${pct}%`
      bar.title = `${hour}:00 — $${(value / 1000000).toFixed(2)}`
    })
  }

  shiftSpend(spend, offset) {
    const result = {}
    for (let h = 0; h < 24; h++) {
      const shifted = ((h + offset) % 24 + 24) % 24
      result[shifted] = (result[shifted] || 0) + (spend[String(h)] || 0)
    }
    return result
  }
}
