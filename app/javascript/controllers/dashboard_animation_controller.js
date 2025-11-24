import { Controller } from "@hotwired/stimulus"

// Dashboard animation controller - animates metric changes when switching attribution models
export default class extends Controller {
  static targets = ["paidSearch", "organicSocial", "email",
                   "barPaidSearch", "barOrganic", "barSocial", "barEmail", "barDirect"]

  // Model-specific data
  models = {
    first_touch: {
      paidSearch: "52.1%",
      organicSocial: "31.2%",
      email: "12.4%",
      bars: { paidSearch: "85%", organic: "55%", social: "45%", email: "25%", direct: "20%" }
    },
    u_shaped: {
      paidSearch: "42.3%",
      organicSocial: "28.7%",
      email: "19.5%",
      bars: { paidSearch: "75%", organic: "50%", social: "65%", email: "40%", direct: "30%" }
    },
    time_decay: {
      paidSearch: "38.6%",
      organicSocial: "35.2%",
      email: "22.8%",
      bars: { paidSearch: "70%", organic: "65%", social: "55%", email: "50%", direct: "35%" }
    }
  }

  connect() {
    // Start with u_shaped as default
    this.currentModel = "u_shaped"
  }

  switchModel(event) {
    const model = event.currentTarget.dataset.model
    if (model && this.models[model] && model !== this.currentModel) {
      this.currentModel = model
      this.animateToModel(model)
    }
  }

  animateToModel(modelName) {
    const data = this.models[modelName]

    // Animate metric values
    if (this.hasPaidSearchTarget) {
      this.animateValue(this.paidSearchTarget, data.paidSearch)
    }
    if (this.hasOrganicSocialTarget) {
      this.animateValue(this.organicSocialTarget, data.organicSocial)
    }
    if (this.hasEmailTarget) {
      this.animateValue(this.emailTarget, data.email)
    }

    // Animate bar heights
    if (this.hasBarPaidSearchTarget) {
      this.barPaidSearchTarget.style.height = data.bars.paidSearch
    }
    if (this.hasBarOrganicTarget) {
      this.barOrganicTarget.style.height = data.bars.organic
    }
    if (this.hasBarSocialTarget) {
      this.barSocialTarget.style.height = data.bars.social
    }
    if (this.hasBarEmailTarget) {
      this.barEmailTarget.style.height = data.bars.email
    }
    if (this.hasBarDirectTarget) {
      this.barDirectTarget.style.height = data.bars.direct
    }
  }

  animateValue(element, newValue) {
    // Simple fade effect
    element.style.opacity = "0.3"
    setTimeout(() => {
      element.textContent = newValue
      element.style.opacity = "1"
    }, 150)
  }
}
