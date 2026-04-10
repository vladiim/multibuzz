import { Controller } from "@hotwired/stimulus"

// Marketing analytics consent banner. Reads/writes the mbuzz_consent
// cookie, updates Google Consent Mode v2 state via gtag, and posts every
// decision to /api/internal/consent for proof-of-consent storage.
//
// Two modes of mounting:
//   - Server renders the banner partial only when the visitor is in
//     the EEA/UK/CH/CA. For those visitors, the banner is initially
//     visible and the user must choose Accept / Reject / Customise.
//   - For non-banner geos, the banner is not rendered. The Stimulus
//     controller still mounts (because of the hidden mount point) so
//     it can record an "auto-grant" consent log row once per session,
//     replicating what a CMP would store.
export default class extends Controller {
  static targets = ["banner", "modal", "analyticsToggle", "adsToggle"]
  static values = {
    autoGrant: { type: Boolean, default: false },
    bannerVersion: { type: String, default: "v1" }
  }

  static COOKIE_NAME = "mbuzz_consent"
  static COOKIE_MAX_AGE_SECONDS = 60 * 60 * 24 * 365 // 1 year
  static COOKIE_REPROMPT_AFTER_MS = 1000 * 60 * 60 * 24 * 365 // 12 months
  static SESSION_AUTO_GRANT_FLAG = "mbuzzConsentAutoGranted"
  static CONSENT_ENDPOINT = "/api/internal/consent"

  static GRANTED = "granted"
  static DENIED = "denied"
  static AD_KEY = "ad"
  static ANALYTICS_KEY = "analytics"

  connect() {
    if (this.hasExistingConsent()) {
      this.applyExistingConsent()
      this.hideBanner()
      return
    }
    if (this.autoGrantValue) {
      this.autoGrantOnce()
      return
    }
    this.showBanner()
  }

  acceptAll() {
    this.persistAndApply({ ad: 1, analytics: 1 })
    this.hideBanner()
  }

  rejectAll() {
    this.persistAndApply({ ad: 0, analytics: 0 })
    this.hideBanner()
  }

  openModal() {
    if (this.hasModalTarget) {
      this.modalTarget.hidden = false
      this.syncModalToggles()
    }
  }

  closeModal() {
    if (this.hasModalTarget) this.modalTarget.hidden = true
  }

  savePreferences() {
    this.persistAndApply({
      ad: this.toggleValue(this.adsToggleTarget),
      analytics: this.toggleValue(this.analyticsToggleTarget)
    })
    this.closeModal()
    this.hideBanner()
  }

  // --- internals ---

  persistAndApply(payload) {
    this.writeCookie(payload)
    this.applyConsentToGtag(payload)
    this.postConsentLog(payload)
  }

  applyExistingConsent() {
    this.applyConsentToGtag(this.readCookie())
  }

  autoGrantOnce() {
    if (window.sessionStorage?.getItem(this.constructor.SESSION_AUTO_GRANT_FLAG)) return
    this.persistAndApply({ ad: 1, analytics: 1 })
    window.sessionStorage?.setItem(this.constructor.SESSION_AUTO_GRANT_FLAG, "1")
  }

  applyConsentToGtag(payload) {
    if (typeof window.gtag !== "function") return
    const ad = payload.ad ? this.constructor.GRANTED : this.constructor.DENIED
    const analytics = payload.analytics ? this.constructor.GRANTED : this.constructor.DENIED
    window.gtag("consent", "update", {
      ad_storage: ad,
      ad_user_data: ad,
      ad_personalization: ad,
      analytics_storage: analytics
    })
  }

  postConsentLog(payload) {
    fetch(this.constructor.CONSENT_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({
        payload: this.gtagPayloadFromCookie(payload),
        banner_version: this.bannerVersionValue,
        visitor_id: this.visitorIdFromCookie()
      })
    }).catch(() => {})
  }

  gtagPayloadFromCookie(payload) {
    return {
      ad_storage: payload.ad ? this.constructor.GRANTED : this.constructor.DENIED,
      ad_user_data: payload.ad ? this.constructor.GRANTED : this.constructor.DENIED,
      ad_personalization: payload.ad ? this.constructor.GRANTED : this.constructor.DENIED,
      analytics_storage: payload.analytics ? this.constructor.GRANTED : this.constructor.DENIED
    }
  }

  hasExistingConsent() {
    const cookie = this.readCookie()
    if (!cookie) return false
    if (!cookie.ts) return true
    return (Date.now() - cookie.ts) < this.constructor.COOKIE_REPROMPT_AFTER_MS
  }

  readCookie() {
    const match = document.cookie.split("; ").find((c) => c.startsWith(`${this.constructor.COOKIE_NAME}=`))
    if (!match) return null
    try {
      return JSON.parse(decodeURIComponent(match.split("=")[1]))
    } catch (e) {
      return null
    }
  }

  writeCookie(payload) {
    const value = encodeURIComponent(JSON.stringify({ ...payload, v: 1, ts: Date.now() }))
    document.cookie = `${this.constructor.COOKIE_NAME}=${value}; max-age=${this.constructor.COOKIE_MAX_AGE_SECONDS}; path=/; SameSite=Lax; Secure`
  }

  visitorIdFromCookie() {
    const match = document.cookie.split("; ").find((c) => c.startsWith("_mbuzz_vid="))
    return match ? match.split("=")[1] : null
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  }

  syncModalToggles() {
    const cookie = this.readCookie() || {}
    if (this.hasAnalyticsToggleTarget) this.analyticsToggleTarget.checked = !!cookie.analytics
    if (this.hasAdsToggleTarget) this.adsToggleTarget.checked = !!cookie.ad
  }

  toggleValue(target) {
    return target?.checked ? 1 : 0
  }

  showBanner() {
    if (this.hasBannerTarget) this.bannerTarget.hidden = false
  }

  hideBanner() {
    if (this.hasBannerTarget) this.bannerTarget.hidden = true
  }
}
