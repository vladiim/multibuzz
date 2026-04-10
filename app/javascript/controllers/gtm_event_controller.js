import { Controller } from "@hotwired/stimulus"

// Pushes a server-rendered event to window.dataLayer on connect. Used by
// conversion success pages (signup, lead) to record GA4 / Google Ads /
// Meta Pixel conversions without inlining a <script>dataLayer.push(...)
// in the view. The view renders a hidden <div> with data attributes; this
// controller reads them once and pushes.
//
// dataLayer is initialised defensively so this controller works whether
// it connects before or after the gtm-loader controller. GTM picks up
// queued pushes when it boots.
export default class extends Controller {
  static values = {
    name: String,
    properties: { type: Object, default: {} }
  }

  connect() {
    if (!this.nameValue) return
    window.dataLayer = window.dataLayer || []
    window.dataLayer.push({ event: this.nameValue, ...this.propertiesValue })
  }
}
