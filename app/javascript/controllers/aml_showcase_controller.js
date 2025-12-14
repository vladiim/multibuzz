import { Controller } from "@hotwired/stimulus"
import hljs from "highlight.js/lib/core"
import ruby from "highlight.js/lib/languages/ruby"

hljs.registerLanguage("ruby", ruby)

const MODELS = {
  first_touch: {
    name: "First Touch Attribution",
    description: "Give 100% credit to the channel that introduced the customer to your brand. Perfect for measuring brand awareness and discovery.",
    bestFor: "Best for: Brand awareness campaigns, top-of-funnel measurement, understanding discovery channels.",
    code: `within_window 30.days do
  apply 1.0, to: touchpoints.first
end`
  },
  last_touch: {
    name: "Last Touch Attribution",
    description: "Give 100% credit to the final touchpoint before conversion. See which channels are closing deals.",
    bestFor: "Best for: Conversion-focused campaigns, bottom-of-funnel optimization, sales attribution.",
    code: `within_window 30.days do
  apply 1.0, to: touchpoints.last
end`
  },
  linear: {
    name: "Linear Attribution",
    description: "Split credit equally across every interaction. Fair, simple, and easy to explain to stakeholders.",
    bestFor: "Best for: Long sales cycles, multi-channel strategies, stakeholder reporting.",
    code: `within_window 30.days do
  apply 1.0, to: touchpoints, distribute: :equal
end`
  },
  time_decay: {
    name: "Time Decay Attribution",
    description: "Recent touchpoints get more credit than earlier ones. Ideal when you want to weight what happened closest to conversion.",
    bestFor: "Best for: Short sales cycles, promotional campaigns, time-sensitive offers.",
    code: `within_window 30.days do
  time_decay half_life: 7.days
end`
  },
  u_shaped: {
    name: "U-Shaped Attribution",
    description: "40% to first touch, 40% to last touch, 20% split across the middle. Rewards both discovery and conversion.",
    bestFor: "Best for: Balanced measurement, valuing both awareness and conversion channels.",
    code: `within_window 30.days do
  apply 0.4, to: touchpoints.first
  apply 0.4, to: touchpoints.last
  apply 0.2, to: touchpoints[1..-2], distribute: :equal
end`
  }
}

export default class extends Controller {
  static targets = ["tab", "code", "modelName", "modelDesc", "bestFor"]

  connect() {
    this.selectModelByKey("first_touch")
  }

  selectModel(event) {
    const model = event.currentTarget.dataset.model
    this.selectModelByKey(model)
  }

  selectModelByKey(model) {
    this.tabTargets.forEach(tab => {
      const isActive = tab.dataset.model === model
      tab.classList.toggle("bg-slate-200", isActive)
      tab.classList.toggle("border-blue-500", isActive)
      tab.classList.toggle("border-transparent", !isActive)
    })

    const data = MODELS[model]
    if (!data) return

    this.codeTarget.innerHTML = hljs.highlight(data.code, { language: "ruby" }).value
    this.modelNameTarget.textContent = data.name
    this.modelDescTarget.textContent = data.description
    this.bestForTarget.textContent = data.bestFor
  }
}
