import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "overlay", "progressBar", "counter",
    "questionView", "questionText", "answers",
    "insightView", "insightIcon", "insightText", "insightSource",
    "loadingView", "resultsView"
  ]

  static values = {
    apiUrl: String,
    claimUrl: String,
    signupUrl: String,
    loggedIn: { type: Boolean, default: false },
    reportUrl: { type: String, default: "" }
  }

  connect() {
    this.currentStep = 0
    this.responses = {}
    this.contextResponses = {}
    this.totalSteps = this.questions.length + this.contextQuestions.length
  }

  // ── Public actions ──

  start(event) {
    event.preventDefault()
    this.currentStep = 0
    this.responses = {}
    this.contextResponses = {}
    this.overlayTarget.classList.add("active")
    document.body.style.overflow = "hidden"
    this.showStep(0)
  }

  close() {
    this.overlayTarget.classList.remove("active")
    document.body.style.overflow = ""
  }

  shareLinkedIn() {
    const url = window.location.origin + "/measurement-maturity-assessment"
    window.open(`https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(url)}`, "_blank")
  }

  shareTwitter() {
    const url = window.location.origin + "/measurement-maturity-assessment"
    const text = "Just took a marketing measurement maturity assessment. Turns out most teams can\u2019t prove their spend works."
    window.open(`https://twitter.com/intent/tweet?text=${encodeURIComponent(text)}&url=${encodeURIComponent(url)}`, "_blank")
  }

  copyLink() {
    const url = window.location.origin + "/measurement-maturity-assessment"
    navigator.clipboard.writeText(url).then(() => {
      const btn = this.element.querySelector("[data-copy-btn]")
      if (btn) {
        const orig = btn.textContent
        btn.textContent = "Copied!"
        setTimeout(() => { btn.textContent = orig }, 2000)
      }
    })
  }

  createAccount() {
    if (this.loggedInValue) {
      window.location.href = this.reportUrlValue
      return
    }
    const token = localStorage.getItem("score_claim_token")
    const url = this.signupUrlValue + (token ? `?claim_token=${token}` : "")
    window.location.href = url
  }

  // ── Step navigation ──

  showStep(step) {
    this.currentStep = step
    const progress = ((step + 1) / this.totalSteps) * 100
    this.progressBarTarget.style.width = `${progress}%`

    this.questionViewTarget.style.display = "none"
    this.insightViewTarget.classList.remove("active")
    this.loadingViewTarget.classList.remove("active")
    this.resultsViewTarget.classList.remove("active")

    if (step < this.questions.length) {
      this.showQuestion(step)
    } else if (step < this.totalSteps) {
      this.showContextQuestion(step - this.questions.length)
    } else {
      this.showLoading()
    }
  }

  showQuestion(index) {
    const q = this.questions[index]
    this.counterTarget.textContent = `${index + 1} of ${this.questions.length}`
    this.questionTextTarget.textContent = q.text
    this.answersTarget.innerHTML = ""

    q.answers.forEach(a => {
      const card = document.createElement("div")
      card.className = "answer-card"
      card.textContent = a.text
      card.addEventListener("click", () => this.selectAnswer(q.id, a, card))
      this.answersTarget.appendChild(card)
    })

    this.questionViewTarget.style.display = "block"
  }

  showContextQuestion(index) {
    const cq = this.contextQuestions[index]
    this.counterTarget.textContent = "Almost done"
    this.questionTextTarget.innerHTML = `<div class="context-label">Quick context to benchmark you against peers</div>${cq.text}`
    this.answersTarget.innerHTML = ""

    cq.answers.forEach(a => {
      const card = document.createElement("div")
      card.className = "answer-card"
      card.textContent = a.text
      card.addEventListener("click", () => this.selectContext(cq.id, a.id, card))
      this.answersTarget.appendChild(card)
    })

    const skip = document.createElement("button")
    skip.className = "context-skip"
    skip.textContent = "Skip"
    skip.addEventListener("click", () => this.showStep(this.currentStep + 1))
    this.answersTarget.appendChild(skip)

    this.questionViewTarget.style.display = "block"
  }

  selectAnswer(qId, answer, card) {
    this.responses[qId] = answer
    this.disableCards(card)

    const insight = this.insights.find(i => i.after === this.currentStep + 1)
    const nextAction = insight
      ? () => this.showInsight(insight)
      : () => this.showStep(this.currentStep + 1)

    this.transitionOut(nextAction)
  }

  selectContext(cId, answerId, card) {
    this.contextResponses[cId] = answerId
    this.disableCards(card)
    this.transitionOut(() => this.showStep(this.currentStep + 1))
  }

  disableCards(selectedCard) {
    this.answersTarget.querySelectorAll(".answer-card").forEach(c => c.style.pointerEvents = "none")
    selectedCard.classList.add("selected")
  }

  transitionOut(callback) {
    this.questionViewTarget.classList.add("exiting")
    setTimeout(() => {
      this.questionViewTarget.classList.remove("exiting")
      callback()
    }, 250)
  }

  showInsight(insight) {
    this.questionViewTarget.style.display = "none"
    this.insightIconTarget.textContent = insight.icon
    this.insightTextTarget.textContent = insight.text
    this.insightSourceTarget.textContent = insight.source
    this.insightViewTarget.classList.add("active")

    const existing = this.insightViewTarget.querySelector(".insight-continue")
    if (existing) existing.remove()

    const btn = document.createElement("button")
    btn.className = "insight-continue"
    btn.textContent = "Continue"
    btn.addEventListener("click", () => {
      this.insightViewTarget.classList.remove("active")
      this.showStep(this.currentStep + 1)
    })
    this.insightViewTarget.appendChild(btn)
  }

  showLoading() {
    this.questionViewTarget.style.display = "none"
    this.counterTarget.textContent = ""
    this.loadingViewTarget.classList.add("active")
    setTimeout(() => {
      this.loadingViewTarget.classList.remove("active")
      this.showResults()
    }, 2500)
  }

  // ── Scoring ──

  calculateScores() {
    let totalWeightedScore = 0
    let totalWeight = 0
    const dimScores = {}
    const dimCounts = {}

    this.questions.forEach(q => {
      const r = this.responses[q.id]
      if (!r) return
      const w = q.weight || 1
      totalWeightedScore += r.score * w
      totalWeight += w

      if (!dimScores[q.dimension]) { dimScores[q.dimension] = 0; dimCounts[q.dimension] = 0 }
      dimScores[q.dimension] += r.score
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

  // ── Results ──

  showResults() {
    const { overallScore, level, dimensions } = this.calculateScores()
    const desc = this.levelDescriptions[level - 1]

    this.saveToApi(overallScore, level, dimensions)
    this.renderFullResults(desc, level, dimensions)

    this.resultsViewTarget.classList.add("active")
    this.counterTarget.textContent = ""
  }

  renderFullResults(desc, level, dimensions) {
    const container = this.resultsViewTarget
    const nextLevel = this.levelDescriptions[Math.min(level, 3)]
    const cta = this.levelCtas[level - 1]
    const articles = this.levelArticles[level - 1]

    container.innerHTML = `
      <div class="result-level-badge" style="background:${desc.bg};color:${desc.color};">
        Level ${level}: ${desc.name}
      </div>
      <p class="result-insight">${desc.insight}</p>

      <div class="result-cta-block">
        <button class="hero-cta" data-action="click->score-assessment#createAccount">
          ${cta.button}
          <svg fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M13 7l5 5m0 0l-5 5m5-5H6"/></svg>
        </button>
        <p class="result-cta-sub">${cta.sub}</p>
      </div>

      <div class="radar-container" id="instant-radar"></div>

      <div class="dimension-breakdown"></div>

      <div class="result-teasers">
        <h3>What's in your full report</h3>
        <div class="teaser-grid">
          <div class="teaser-card">
            <div class="teaser-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/></svg></div>
            <strong>Your roadmap to Level ${Math.min(level + 1, 4)}</strong>
            <p>${cta.roadmapTeaser}</p>
          </div>
          <div class="teaser-card">
            <div class="teaser-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 21H4.6c-.56 0-.84 0-1.054-.109a1 1 0 01-.437-.437C3 20.24 3 19.96 3 19.4V3"/><path d="M7 14l4-4 4 4 6-6"/></svg></div>
            <strong>Business case for your CFO</strong>
            <p>Research-backed waste estimates tailored to your spend level. Copy-paste ready for a board slide.</p>
          </div>
          <div class="teaser-card">
            <div class="teaser-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4-4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 00-3-3.87M16 3.13a4 4 0 010 7.75"/></svg></div>
            <strong>Get your team's perspective</strong>
            <p>Assign specific questions to colleagues. The gap between how roles see measurement is usually the real insight.</p>
          </div>
        </div>
      </div>

      <div class="result-articles">
        <h3>Relevant reading based on your results</h3>
        <div class="article-links">
          ${articles.map(a => `<a href="${a.url}?utm_source=score&utm_medium=results&utm_content=level${level}" class="article-link">${a.title} <span>\u2192</span></a>`).join("")}
        </div>
      </div>

      <div class="result-share">
        <div class="share-row">
          <button class="secondary-action" data-action="click->score-assessment#shareLinkedIn">LinkedIn</button>
          <button class="secondary-action" data-action="click->score-assessment#shareTwitter">X / Twitter</button>
          <button class="secondary-action" data-action="click->score-assessment#copyLink" data-copy-btn>Copy Link</button>
        </div>
      </div>
    `

    this.renderRadarInto(container.querySelector("#instant-radar"), dimensions, 500)
    this.renderDimensionBars(container.querySelector(".dimension-breakdown"), dimensions)
  }

  renderResultBadge(desc, level) {
    this.resultBadgeTarget.style.background = desc.bg
    this.resultBadgeTarget.style.color = desc.color
    this.resultBadgeTarget.innerHTML = `Level ${level}: ${desc.name}`
  }

  renderDimensionBreakdown(dimensions) {
    this.renderDimensionBars(this.dimensionBreakdownTarget, dimensions)
  }

  renderDimensionBars(container, dimensions) {
    container.innerHTML = `<h3 style="font-size:16px;font-weight:700;margin-bottom:16px;">Dimension Breakdown</h3>`

    const dimOrder = ["reporting", "attribution", "experimentation", "forecasting", "channels", "infrastructure"]
    let strongest = { dim: "", score: 0 }
    let weakest = { dim: "", score: 5 }

    dimOrder.forEach(d => {
      const score = dimensions[d] || 1
      if (score > strongest.score) strongest = { dim: d, score }
      if (score < weakest.score) weakest = { dim: d, score }
    })

    dimOrder.forEach(d => {
      const score = dimensions[d] || 1
      const pct = (score / 4) * 100
      let barColor = "var(--accent)"
      if (d === strongest.dim) barColor = "var(--green)"
      if (d === weakest.dim) barColor = "var(--red)"
      const dimLevel = score < 1.8 ? 1 : score < 2.5 ? 2 : score < 3.3 ? 3 : 4

      const row = document.createElement("div")
      row.className = "dimension-row"
      row.innerHTML = `
        <div class="dimension-name">${this.dimensionLabels[d]}</div>
        <div class="dimension-bar-bg"><div class="dimension-bar" style="width:0%;background:${barColor};"></div></div>
        <div class="dimension-score" style="color:${barColor}">L${dimLevel}</div>
      `
      container.appendChild(row)
      setTimeout(() => { row.querySelector(".dimension-bar").style.width = `${pct}%` }, 100)
    })

    const callout = document.createElement("div")
    callout.style.cssText = "margin-top:20px;padding:16px 20px;background:var(--bg-card);border-radius:var(--radius);border:1px solid var(--border);font-size:14px;color:var(--text-muted);line-height:1.6;"
    callout.innerHTML = `
      <strong style="color:var(--green);">Strongest:</strong> ${this.dimensionLabels[strongest.dim]}<br>
      <strong style="color:var(--red);">Biggest gap:</strong> ${this.dimensionLabels[weakest.dim]} \u2014 this is where measurement value is most likely being lost.
    `
    container.appendChild(callout)
  }

  renderRadar(dimensions) {
    this.renderRadarInto(this.radarChartTarget, dimensions, 380)
  }

  renderRadarInto(container, dimensions, size) {
    container.innerHTML = ""
    const pad = 80
    const totalSize = size + pad * 2
    const cx = totalSize / 2, cy = totalSize / 2, maxR = size * 0.36
    const dims = ["reporting", "attribution", "experimentation", "forecasting", "channels", "infrastructure"]
    const labels = ["Reporting", "Attribution", "Experimentation", "Forecasting", "Channels", "Infrastructure"]
    const n = dims.length

    let svg = `<svg width="100%" viewBox="0 0 ${totalSize} ${totalSize}" style="font-family:Inter,sans-serif">`

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

    const dataPoints = dims.map((d, i) => {
      const radius = ((dimensions[d] || 1) / 4) * maxR
      const angle = (Math.PI * 2 * i) / n - Math.PI / 2
      return `${cx + radius * Math.cos(angle)},${cy + radius * Math.sin(angle)}`
    })
    svg += `<polygon points="${dataPoints.join(" ")}" fill="rgba(77,127,255,0.15)" stroke="var(--accent)" stroke-width="2"/>`

    dims.forEach((d, i) => {
      const radius = ((dimensions[d] || 1) / 4) * maxR
      const angle = (Math.PI * 2 * i) / n - Math.PI / 2
      svg += `<circle cx="${cx + radius * Math.cos(angle)}" cy="${cy + radius * Math.sin(angle)}" r="4" fill="var(--accent)"/>`

      const lx = cx + (maxR + 40) * Math.cos(angle)
      const ly = cy + (maxR + 40) * Math.sin(angle)
      const anchor = Math.abs(angle + Math.PI / 2) < 0.1 ? "middle" : (lx > cx ? "start" : "end")
      svg += `<text x="${lx}" y="${ly + 5}" text-anchor="${anchor}" fill="#8888a0" font-size="13" font-weight="500">${labels[i]}</text>`
    })

    svg += "</svg>"
    container.innerHTML = svg
  }

  // ── API ──

  saveToApi(overallScore, level, dimensions) {
    const answersPayload = Object.entries(this.responses).map(([qId, ans]) => ({
      question_id: qId, answer_id: ans.id, score: ans.score
    }))

    const payload = {
      assessment: {
        overall_score: parseFloat(overallScore.toFixed(2)),
        overall_level: level,
        dimension_scores: dimensions,
        answers: answersPayload,
        context: this.contextResponses,
        source: this.detectSource(),
        utm_params: this.extractUtmParams()
      }
    }

    fetch(this.apiUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json" },
      body: JSON.stringify(payload)
    })
    .then(r => r.json())
    .then(data => {
      if (data.claim_token) localStorage.setItem("score_claim_token", data.claim_token)
      if (data.id) localStorage.setItem("score_assessment_id", data.id)
    })
    .catch(err => console.error("[score] save failed:", err))
  }

  detectSource() {
    const params = new URLSearchParams(window.location.search)
    if (params.get("gclid")) return "ppc_google"
    if (params.get("utm_source")) return `utm_${params.get("utm_source")}`
    if (document.referrer.includes("linkedin")) return "social_linkedin"
    return "organic"
  }

  extractUtmParams() {
    const params = new URLSearchParams(window.location.search)
    const utms = {}
    ;["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term"].forEach(key => {
      if (params.get(key)) utms[key] = params.get(key)
    })
    return utms
  }

  // ── Static data ──

  get dimensionLabels() {
    return {
      reporting: "Reporting & Analytics",
      attribution: "Attribution & Credit",
      experimentation: "Experimentation",
      forecasting: "Forecasting & Optimisation",
      channels: "Channel Coverage",
      infrastructure: "Data Infrastructure"
    }
  }

  get levelDescriptions() {
    return [
      { level: 1, name: "Ad Hoc",       color: "var(--red)",    bg: "rgba(255,77,106,0.12)",  insight: "You\u2019re relying on platform-reported data. Every channel is grading its own homework \u2014 and they\u2019re all giving themselves A+. The good news: the biggest ROI gain is moving from Level 1 to Level 2." },
      { level: 2, name: "Operational",   color: "var(--accent)", bg: "rgba(77,127,255,0.12)",  insight: "You\u2019ve built a unified view and started questioning the numbers. That puts you ahead of most marketing teams. Next step: start cross-validating with a second method." },
      { level: 3, name: "Analytical",    color: "#a78bfa",       bg: "rgba(167,139,250,0.12)", insight: "You\u2019re triangulating across methods. That\u2019s rare and valuable. The gap to close: structured experimentation. Running even one geo-holdout test would put you near the top." },
      { level: 4, name: "Leader",        color: "var(--green)",  bg: "rgba(77,255,145,0.12)",  insight: "You can prove causation and predict outcomes. Very few companies get here. Measurement is a competitive advantage for your company, not just a reporting function." }
    ]
  }

  get insights() {
    return [
      { after: 3,  icon: "\u{1F4E1}", text: "Companies using server-side tracking capture 30\u201340% more conversion data than client-side only. Ad blockers and ITP eat the rest.", source: "mbuzz benchmark data" },
      { after: 6,  icon: "\u{1F4B8}", text: "The average marketer reallocates budget once a quarter. Leaders do it weekly. The gap between these two approaches compounds over 12 months.", source: "" },
      { after: 9,  icon: "\u{1F3AF}", text: "Only 39% of companies use more than one measurement method. Let\u2019s see where you stand.", source: "IAB State of Data 2026" }
    ]
  }

  get questions() {
    return [
      { id: "q1", dimension: "reporting", text: "When your CEO asks \"is marketing working?\", where does the answer come from?", answers: [
        { id: "a", text: "Each channel\u2019s own dashboard \u2014 Google Ads, Meta, LinkedIn, etc.", score: 1.0 },
        { id: "b", text: "Google Analytics or a BI tool that pulls everything together", score: 1.5 },
        { id: "c", text: "An independent analytics platform with its own tracking", score: 2.5 },
        { id: "d", text: "Multiple methods compared \u2014 we triangulate before answering", score: 3.5 },
        { id: "e", text: "I\u2019m not sure \u2014 we don\u2019t have a consistent answer", score: 1.0 }
      ]},
      { id: "q2", dimension: "attribution", weight: 1.5, text: "You made 100 sales yesterday. Google Ads claims it drove 70 of them. Meta claims 40. What do you do?", answers: [
        { id: "a", text: "Report each platform\u2019s numbers separately", score: 1.0 },
        { id: "b", text: "Pick one platform as the \u201cofficial\u201d source and ignore the others", score: 1.0 },
        { id: "c", text: "Use a multi-touch model to deduplicate and assign fractional credit", score: 2.5 },
        { id: "d", text: "Run the MTA numbers, then validate with a holdout test or MMM", score: 3.5 },
        { id: "e", text: "I\u2019m not sure how we\u2019d handle this", score: 1.0 }
      ]},
      { id: "q3", dimension: "infrastructure", text: "How does your marketing data get collected?", answers: [
        { id: "a", text: "JavaScript tags on the website (GA4, platform pixels)", score: 1.0 },
        { id: "b", text: "Tag manager with some server-side forwarding", score: 1.5 },
        { id: "c", text: "Server-side tracking as primary, client-side as fallback", score: 2.5 },
        { id: "d", text: "Server-side with first-party data, unified in a warehouse", score: 3.5 },
        { id: "e", text: "I\u2019m not sure what our tracking setup looks like", score: 1.0 }
      ]},
      { id: "q4", dimension: "channels", text: "Which channels are included in your measurement? (Pick the closest match)", answers: [
        { id: "a", text: "Just paid search and paid social", score: 1.0 },
        { id: "b", text: "Paid channels plus organic search and email", score: 2.0 },
        { id: "c", text: "All digital channels including SEO, email, referral, and affiliates", score: 3.0 },
        { id: "d", text: "Digital plus offline \u2014 TV, events, direct mail, brand campaigns", score: 4.0 },
        { id: "e", text: "We don\u2019t really have a unified measurement model", score: 1.0 }
      ]},
      { id: "q5", dimension: "experimentation", text: "In the last 12 months, how many times have you deliberately turned OFF a paid channel to measure its true impact?", answers: [
        { id: "a", text: "Never \u2014 we wouldn\u2019t risk the lost revenue", score: 1.0 },
        { id: "b", text: "We\u2019ve discussed it but haven\u2019t done it", score: 1.5 },
        { id: "c", text: "Once or twice, informally", score: 2.5 },
        { id: "d", text: "We have a structured experimentation programme with regular holdouts", score: 3.5 },
        { id: "e", text: "I\u2019m not sure", score: 1.0 }
      ]},
      { id: "q6", dimension: "forecasting", text: "How do you set next quarter\u2019s channel budgets?", answers: [
        { id: "a", text: "Last year\u2019s budget plus or minus a percentage", score: 1.0 },
        { id: "b", text: "Based on platform-reported ROAS or CPA targets", score: 1.5 },
        { id: "c", text: "Scenario modelling \u2014 \u201cwhat if we shift 20% from SEM to social?\u201d", score: 2.5 },
        { id: "d", text: "Incrementality-based optimisation \u2014 budget flows to proven marginal returns", score: 3.5 },
        { id: "e", text: "Someone above me decides \u2014 I\u2019m not sure", score: 1.0 }
      ]},
      { id: "q7", dimension: "attribution", text: "Which best describes how marketing gets credit for conversions?", answers: [
        { id: "a", text: "Last-click \u2014 whatever the customer clicked last gets all credit", score: 1.0 },
        { id: "b", text: "Platform-reported \u2014 Google claims Google\u2019s conversions, Meta claims Meta\u2019s", score: 1.0 },
        { id: "c", text: "We compare multiple models: first-touch, linear, time-decay, position-based", score: 2.5 },
        { id: "d", text: "Multi-touch attribution calibrated or validated by incrementality testing", score: 3.5 },
        { id: "e", text: "I don\u2019t know what model we use", score: 1.0 }
      ]},
      { id: "q8", dimension: "reporting", text: "When a campaign underperforms, how quickly can you identify the problem and reallocate?", answers: [
        { id: "a", text: "End of quarter or during annual review", score: 1.0 },
        { id: "b", text: "Monthly, when we review dashboards", score: 1.5 },
        { id: "c", text: "Weekly \u2014 automated alerts and regular optimisation cycles", score: 2.5 },
        { id: "d", text: "Near real-time \u2014 automated rules or models trigger reallocation", score: 3.5 },
        { id: "e", text: "We usually don\u2019t reallocate mid-campaign", score: 1.0 }
      ]},
      { id: "q9", dimension: "infrastructure", text: "How prepared is your measurement for a world without third-party cookies?", answers: [
        { id: "a", text: "We haven\u2019t thought about it much", score: 1.0 },
        { id: "b", text: "We\u2019re aware it\u2019s coming but haven\u2019t changed our approach", score: 1.0 },
        { id: "c", text: "We\u2019ve started building first-party data and server-side tracking", score: 2.5 },
        { id: "d", text: "Our measurement works without cookies \u2014 MMM, first-party data, incrementality", score: 3.5 },
        { id: "e", text: "I\u2019m not sure what impact it will have", score: 1.0 }
      ]},
      { id: "q10", dimension: "experimentation", weight: 1.5, text: "If your CFO asked you to PROVE that marketing spend generates incremental revenue, could you?", answers: [
        { id: "a", text: "No \u2014 we\u2019d show platform-reported ROAS and hope for the best", score: 1.0 },
        { id: "b", text: "We\u2019d show before/after data or trend correlations", score: 1.5 },
        { id: "c", text: "We could show MTA data from an independent source, but not causal proof", score: 2.5 },
        { id: "d", text: "Yes \u2014 we\u2019ve run controlled experiments that isolate marketing\u2019s causal impact", score: 4.0 },
        { id: "e", text: "I\u2019m not sure what \u201cincremental\u201d means in this context", score: 1.0 }
      ]}
    ]
  }

  get levelCtas() {
    return [
      { button: "Get Your Roadmap to Level 2", sub: "Independent tracking, cross-channel dedup, and 30-40% more data captured", roadmapTeaser: "5 specific actions to deploy independent tracking, deduplicate conversions, and connect CRM revenue to touchpoints." },
      { button: "Get Your Roadmap to Level 3", sub: "MMM cross-validation, geo-holdout experiments, scenario modelling", roadmapTeaser: "4 actions to add a second measurement method, run your first holdout experiment, and build scenario-based budget models." },
      { button: "Get Your Roadmap to Level 4", sub: "Continuous incrementality testing, causal forecasting, automated reallocation", roadmapTeaser: "3 actions to establish structured experimentation, calibrate MTA with causal data, and automate budget reallocation." },
      { button: "View Your Full Report", sub: "You\u2019re at the top \u2014 see your full dimension breakdown and share with your team", roadmapTeaser: "Maintain your edge: testing cadence, new channel expansion, and methodology documentation." }
    ]
  }

  get levelArticles() {
    return [
      [ // Level 1
        { title: "What is multi-touch attribution?", url: "/articles/what-is-multi-touch-attribution" },
        { title: "Why platform reports don\u2019t match", url: "/articles/platform-reports-dont-match" },
        { title: "Server-side vs client-side tracking", url: "/articles/server-side-vs-client-side-tracking" },
        { title: "GA4 attribution models removed \u2014 now what?", url: "/articles/ga4-attribution-models-removed" },
        { title: "How to choose an attribution model", url: "/articles/how-to-choose-attribution-model" }
      ],
      [ // Level 2
        { title: "MTA vs MMM: when to use which", url: "/articles/mta-vs-mmm" },
        { title: "How to shift budget between channels", url: "/articles/shift-budget-between-channels" },
        { title: "When to change your marketing budget", url: "/articles/when-to-change-marketing-budget" },
        { title: "The triangulation approach", url: "/articles/mta-mmm-incrementality-triangulation" }
      ],
      [ // Level 3
        { title: "How to test budget changes safely", url: "/articles/how-to-test-budget-changes" },
        { title: "Diminishing returns in ad spend", url: "/articles/diminishing-returns-ad-spend" },
        { title: "The algorithm tax: pause, reduce, restart", url: "/articles/algorithm-tax-pause-reduce-restart" }
      ],
      [ // Level 4
        { title: "Bottom-up revenue forecasting", url: "/articles/bottom-up-revenue-forecast" },
        { title: "Funnel-stage attribution", url: "/articles/funnel-stage-attribution" }
      ]
    ]
  }

  get contextQuestions() {
    return [
      { id: "c1", text: "How many employees does your company have?", answers: [
        { id: "1-10", text: "1\u201310" }, { id: "11-50", text: "11\u201350" }, { id: "51-200", text: "51\u2013200" }, { id: "201-1000", text: "201\u20131,000" }, { id: "1000+", text: "1,000+" }
      ]},
      { id: "c2", text: "What\u2019s your approximate annual paid media spend?", answers: [
        { id: "<100k", text: "Under $100K" }, { id: "100k-500k", text: "$100K\u2013$500K" }, { id: "500k-2m", text: "$500K\u2013$2M" }, { id: "2m-10m", text: "$2M\u2013$10M" }, { id: "10m+", text: "$10M+" }, { id: "na", text: "Prefer not to say" }
      ]},
      { id: "c3", text: "Which best describes your role?", answers: [
        { id: "marketing", text: "Marketing / Growth" }, { id: "ops", text: "Marketing Ops" }, { id: "data", text: "Data / Analytics" }, { id: "engineering", text: "Engineering" }, { id: "exec", text: "Executive / C-suite" }, { id: "other", text: "Other" }
      ]}
    ]
  }
}
