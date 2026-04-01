// Shared radar chart renderer — single source of truth.
// Used by: score_radar_controller, score_assessment_controller, score_results_controller, score_radar_demo_controller

const DIMENSIONS = ["reporting", "attribution", "experimentation", "forecasting", "channels", "infrastructure"]
const LABELS = ["Reporting", "Attribution", "Experimentation", "Forecasting", "Channels", "Infrastructure"]
const LEVEL_LABELS = ["", "L1", "L2", "L3", "L4"]
const LEVEL_COUNT = 4
const GRID_STROKE = "rgba(255,255,255,0.25)"
const AXIS_STROKE = "rgba(255,255,255,0.2)"
const LEVEL_LABEL_FILL = "rgba(255,255,255,0.45)"
const LABEL_FILL = "rgba(255,255,255,0.7)"
const ACCENT = "var(--accent, #4d7fff)"
const DOT_STROKE = "#0d0d1a"
const DATA_FILL = "rgba(77,127,255,0.2)"

// Renders an SVG radar chart into a container element.
// dimensions: { reporting: 2.5, attribution: 3.0, ... }
// options: { animate: false } — if true, starts polygon at center for CSS transition
export function renderRadar(container, dimensions, options = {}) {
  const chartSize = 320
  const pad = 80
  const totalSize = chartSize + pad * 2
  const cx = totalSize / 2
  const cy = totalSize / 2
  const maxR = chartSize * 0.36
  const n = DIMENSIONS.length
  const animate = options.animate || false

  let svg = `<svg width="100%" viewBox="0 0 ${totalSize} ${totalSize}" style="font-family:Inter,sans-serif">`

  // Grid rings with level labels
  for (let r = 1; r <= LEVEL_COUNT; r++) {
    const radius = (r / LEVEL_COUNT) * maxR
    const points = Array.from({ length: n }, (_, i) => {
      const angle = (Math.PI * 2 * i) / n - Math.PI / 2
      return `${cx + radius * Math.cos(angle)},${cy + radius * Math.sin(angle)}`
    })
    svg += `<polygon points="${points.join(" ")}" fill="none" stroke="${GRID_STROKE}" stroke-width="1"/>`
    const la = (Math.PI * 2 * 1) / n - Math.PI / 2
    svg += `<text x="${cx + radius * Math.cos(la) + 8}" y="${cy + radius * Math.sin(la) - 4}" fill="${LEVEL_LABEL_FILL}" font-size="10" font-weight="600">${LEVEL_LABELS[r]}</text>`
  }

  // Axis lines
  for (let i = 0; i < n; i++) {
    const angle = (Math.PI * 2 * i) / n - Math.PI / 2
    svg += `<line x1="${cx}" y1="${cy}" x2="${cx + maxR * Math.cos(angle)}" y2="${cy + maxR * Math.sin(angle)}" stroke="${AXIS_STROKE}" stroke-width="1"/>`
  }

  // Data polygon
  const dataPoints = DIMENSIONS.map((d, i) => {
    const radius = ((dimensions[d] || 1) / LEVEL_COUNT) * maxR
    const angle = (Math.PI * 2 * i) / n - Math.PI / 2
    return `${cx + radius * Math.cos(angle)},${cy + radius * Math.sin(angle)}`
  })

  if (animate) {
    const centerPoints = Array.from({ length: n }, () => `${cx},${cy}`)
    svg += `<polygon class="radar-data-polygon" points="${centerPoints.join(" ")}" fill="${DATA_FILL}" stroke="${ACCENT}" stroke-width="2.5" data-target="${dataPoints.join(" ")}"/>`
  } else {
    svg += `<polygon points="${dataPoints.join(" ")}" fill="${DATA_FILL}" stroke="${ACCENT}" stroke-width="2.5"/>`
  }

  // Data dots and labels
  DIMENSIONS.forEach((d, i) => {
    const radius = ((dimensions[d] || 1) / LEVEL_COUNT) * maxR
    const angle = (Math.PI * 2 * i) / n - Math.PI / 2
    const dotCx = cx + radius * Math.cos(angle)
    const dotCy = cy + radius * Math.sin(angle)

    if (animate) {
      svg += `<circle class="radar-data-dot" cx="${cx}" cy="${cy}" data-tx="${dotCx}" data-ty="${dotCy}" r="5" fill="${ACCENT}" stroke="${DOT_STROKE}" stroke-width="2" opacity="0"/>`
    } else {
      svg += `<circle cx="${dotCx}" cy="${dotCy}" r="5" fill="${ACCENT}" stroke="${DOT_STROKE}" stroke-width="2"/>`
    }

    const lx = cx + (maxR + 40) * Math.cos(angle)
    const ly = cy + (maxR + 40) * Math.sin(angle)
    const anchor = Math.abs(angle + Math.PI / 2) < 0.1 ? "middle" : (lx > cx ? "start" : "end")
    svg += `<text x="${lx}" y="${ly + 5}" text-anchor="${anchor}" fill="${LABEL_FILL}" font-size="13" font-weight="600">${LABELS[i]}</text>`
  })

  svg += "</svg>"
  container.innerHTML = svg
}

// Triggers the animation for a radar rendered with animate: true
export function animateRadar(container) {
  requestAnimationFrame(() => {
    const poly = container.querySelector(".radar-data-polygon")
    if (poly) poly.setAttribute("points", poly.dataset.target)

    container.querySelectorAll(".radar-data-dot").forEach((dot, i) => {
      setTimeout(() => {
        dot.setAttribute("cx", dot.dataset.tx)
        dot.setAttribute("cy", dot.dataset.ty)
        dot.setAttribute("opacity", "1")
      }, 200 + i * 80)
    })
  })
}
