import { Controller } from "@hotwired/stimulus"
import { renderRadar } from "helpers/radar_chart"

// Renders shared assessment results from a decoded answer array.
// All scoring happens client-side — no database lookup needed.
export default class extends Controller {
  static targets = ["loading", "content", "badge", "insight", "radar", "dimensions"]
  static values = { answers: Array }

  connect() {
    const results = this.calculateScores()
    this.renderResults(results)
    this.loadingTarget.style.display = "none"
    this.contentTarget.style.display = "block"
  }

  calculateScores() {
    const questions = this.questions
    const answerIndices = this.answersValue
    let totalWeightedScore = 0
    let totalWeight = 0
    const dimScores = {}
    const dimCounts = {}

    questions.forEach((q, i) => {
      const answerIndex = answerIndices[i]
      if (answerIndex === undefined || !q.answers[answerIndex]) return
      const score = q.answers[answerIndex].score
      const w = q.weight || 1
      totalWeightedScore += score * w
      totalWeight += w

      if (!dimScores[q.dimension]) { dimScores[q.dimension] = 0; dimCounts[q.dimension] = 0 }
      dimScores[q.dimension] += score
      dimCounts[q.dimension] += 1
    })

    const overallScore = totalWeight > 0 ? totalWeightedScore / totalWeight : 1
    const dimensions = {}
    Object.keys(dimScores).forEach(d => { dimensions[d] = dimScores[d] / dimCounts[d] })

    let level
    if (overallScore < 1.8) level = 1
    else if (overallScore < 2.5) level = 2
    else if (overallScore < 3.3) level = 3
    else level = 4

    return { overallScore, level, dimensions }
  }

  renderResults({ level, dimensions }) {
    const desc = this.levelDescriptions[level - 1]

    this.badgeTarget.style.background = desc.bg
    this.badgeTarget.style.color = desc.color
    this.badgeTarget.textContent = `Level ${level}: ${desc.name}`
    this.insightTarget.textContent = desc.insight

    renderRadar(this.radarTarget, dimensions)
    this.renderDimensionCards(dimensions)
  }

  renderDimensionCards(dimensions) {
    const dimLabels = {
      reporting: "Reporting & Analytics", attribution: "Attribution & Credit",
      experimentation: "Experimentation", forecasting: "Forecasting & Optimisation",
      channels: "Channel Coverage", infrastructure: "Data Infrastructure"
    }
    const levelNames = { 1: "Ad Hoc", 2: "Operational", 3: "Analytical", 4: "Leader" }
    const levelColors = { 1: "var(--red)", 2: "var(--accent)", 3: "#a78bfa", 4: "var(--green)" }

    let html = ""
    Object.entries(dimLabels).forEach(([key, label]) => {
      const score = dimensions[key] || 1
      const dimLevel = score < 1.8 ? 1 : score < 2.5 ? 2 : score < 3.3 ? 3 : 4
      html += `
        <div class="dim-summary-card">
          <h4>${label}</h4>
          <div class="dim-score" style="color: ${levelColors[dimLevel]};">Level ${dimLevel}</div>
          <div class="dim-label">${levelNames[dimLevel]}</div>
        </div>`
    })
    this.dimensionsTarget.innerHTML = html
  }

  get levelDescriptions() {
    return [
      { level: 1, name: "Ad Hoc",       color: "var(--red)",    bg: "rgba(255,77,106,0.12)",  insight: "Relying on platform-reported data. Every channel is grading its own homework." },
      { level: 2, name: "Operational",   color: "var(--accent)", bg: "rgba(77,127,255,0.12)",  insight: "Unified view with independent tracking. Ahead of most marketing teams." },
      { level: 3, name: "Analytical",    color: "#a78bfa",       bg: "rgba(167,139,250,0.12)", insight: "Triangulating across methods. Rare and valuable. Close the gap with structured experimentation." },
      { level: 4, name: "Leader",        color: "var(--green)",  bg: "rgba(77,255,145,0.12)",  insight: "Proving causation and predicting outcomes. Measurement is a competitive advantage." }
    ]
  }

  get questions() {
    return [
      { id: "q1", dimension: "reporting", answers: [
        { score: 1.0 }, { score: 1.5 }, { score: 2.5 }, { score: 3.5 }, { score: 1.0 }
      ]},
      { id: "q2", dimension: "attribution", weight: 1.5, answers: [
        { score: 1.0 }, { score: 1.0 }, { score: 2.5 }, { score: 3.5 }, { score: 1.0 }
      ]},
      { id: "q3", dimension: "infrastructure", answers: [
        { score: 1.0 }, { score: 1.5 }, { score: 2.5 }, { score: 3.5 }, { score: 1.0 }
      ]},
      { id: "q4", dimension: "channels", answers: [
        { score: 1.0 }, { score: 2.0 }, { score: 3.0 }, { score: 4.0 }, { score: 1.0 }
      ]},
      { id: "q5", dimension: "experimentation", answers: [
        { score: 1.0 }, { score: 1.5 }, { score: 2.5 }, { score: 3.5 }, { score: 1.0 }
      ]},
      { id: "q6", dimension: "forecasting", answers: [
        { score: 1.0 }, { score: 1.5 }, { score: 2.5 }, { score: 3.5 }, { score: 1.0 }
      ]},
      { id: "q7", dimension: "attribution", answers: [
        { score: 1.0 }, { score: 1.0 }, { score: 2.5 }, { score: 3.5 }, { score: 1.0 }
      ]},
      { id: "q8", dimension: "reporting", answers: [
        { score: 1.0 }, { score: 1.5 }, { score: 2.5 }, { score: 3.5 }, { score: 1.0 }
      ]},
      { id: "q9", dimension: "infrastructure", answers: [
        { score: 1.0 }, { score: 1.0 }, { score: 2.5 }, { score: 3.5 }, { score: 1.0 }
      ]},
      { id: "q10", dimension: "experimentation", weight: 1.5, answers: [
        { score: 1.0 }, { score: 1.5 }, { score: 2.5 }, { score: 4.0 }, { score: 1.0 }
      ]}
    ]
  }
}
