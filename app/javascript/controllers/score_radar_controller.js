import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { dimensions: Object }

  connect() {
    this.render()
  }

  render() {
    const dims = this.dimensionsValue
    const size = 400
    const cx = size / 2
    const cy = size / 2
    const maxR = 150
    const keys = ["reporting", "attribution", "experimentation", "forecasting", "channels", "infrastructure"]
    const labels = ["Reporting", "Attribution", "Experimentation", "Forecasting", "Channels", "Infrastructure"]
    const n = keys.length

    let svg = `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" style="font-family:Inter,sans-serif">`

    for (let r = 1; r <= 4; r++) {
      const radius = (r / 4) * maxR
      const points = Array.from({ length: n }, (_, i) => {
        const angle = (Math.PI * 2 * i) / n - Math.PI / 2
        return `${cx + radius * Math.cos(angle)},${cy + radius * Math.sin(angle)}`
      })
      svg += `<polygon points="${points.join(" ")}" fill="none" stroke="rgba(255,255,255,0.06)" stroke-width="1"/>`
    }

    for (let i = 0; i < n; i++) {
      const angle = (Math.PI * 2 * i) / n - Math.PI / 2
      svg += `<line x1="${cx}" y1="${cy}" x2="${cx + maxR * Math.cos(angle)}" y2="${cy + maxR * Math.sin(angle)}" stroke="rgba(255,255,255,0.06)" stroke-width="1"/>`
    }

    const dataPoints = keys.map((d, i) => {
      const radius = ((dims[d] || 1) / 4) * maxR
      const angle = (Math.PI * 2 * i) / n - Math.PI / 2
      return `${cx + radius * Math.cos(angle)},${cy + radius * Math.sin(angle)}`
    })
    svg += `<polygon points="${dataPoints.join(" ")}" fill="rgba(77,127,255,0.15)" stroke="#4d7fff" stroke-width="2"/>`

    keys.forEach((d, i) => {
      const radius = ((dims[d] || 1) / 4) * maxR
      const angle = (Math.PI * 2 * i) / n - Math.PI / 2
      svg += `<circle cx="${cx + radius * Math.cos(angle)}" cy="${cy + radius * Math.sin(angle)}" r="4" fill="#4d7fff"/>`

      const lx = cx + (maxR + 30) * Math.cos(angle)
      const ly = cy + (maxR + 30) * Math.sin(angle)
      const anchor = Math.abs(angle + Math.PI / 2) < 0.1 ? "middle" : (lx > cx ? "start" : "end")
      svg += `<text x="${lx}" y="${ly + 4}" text-anchor="${anchor}" fill="#55556a" font-size="12" font-weight="500">${labels[i]}</text>`
    })

    svg += "</svg>"
    this.element.innerHTML = svg
  }
}
