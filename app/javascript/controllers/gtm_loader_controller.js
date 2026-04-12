import { Controller } from "@hotwired/stimulus"

// Boots window.dataLayer + window.gtag, sets the Consent Mode v2 default
// state computed server-side, then schedules the GTM script load via
// requestIdleCallback so initial render is unaffected by vendor SDKs.
//
// All marketing analytics JavaScript lives in Stimulus controllers — there
// are no inline <script> tags for this feature anywhere.
export default class extends Controller {
  static values = {
    containerId: String,
    consentDefault: String
  }

  static GTM_BASE_URL = "https://www.googletagmanager.com/gtm.js"
  static IDLE_TIMEOUT_MS = 2000

  static GRANTED = "granted"
  static DENIED = "denied"
  static CONSENT_TIMEOUT_MS = 500

  connect() {
    this.initDataLayer()
    this.setConsentDefaults()
    this.scheduleGtmLoad()
  }

  initDataLayer() {
    window.dataLayer = window.dataLayer || []
    window.gtag = window.gtag || function () { window.dataLayer.push(arguments) }
  }

  setConsentDefaults() {
    window.gtag("consent", "default", this.consentPayload())
  }

  consentPayload() {
    const value = this.consentDefaultValue === this.constructor.DENIED
      ? this.constructor.DENIED
      : this.constructor.GRANTED
    return {
      ad_storage: value,
      ad_user_data: value,
      ad_personalization: value,
      analytics_storage: value,
      functionality_storage: this.constructor.GRANTED,
      security_storage: this.constructor.GRANTED,
      wait_for_update: this.constructor.CONSENT_TIMEOUT_MS
    }
  }

  scheduleGtmLoad() {
    if ("requestIdleCallback" in window) {
      window.requestIdleCallback(() => this.injectGtmScript(), { timeout: this.constructor.IDLE_TIMEOUT_MS })
    } else {
      window.setTimeout(() => this.injectGtmScript(), this.constructor.IDLE_TIMEOUT_MS)
    }
  }

  injectGtmScript() {
    window.dataLayer.push({ "gtm.start": new Date().getTime(), event: "gtm.js" })
    const script = document.createElement("script")
    script.async = true
    script.src = `${this.constructor.GTM_BASE_URL}?id=${encodeURIComponent(this.containerIdValue)}`
    document.head.appendChild(script)
  }
}
