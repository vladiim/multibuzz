import { Controller } from "@hotwired/stimulus"
import hljs from "highlight.js/lib/core"
import ruby from "highlight.js/lib/languages/ruby"

hljs.registerLanguage("ruby", ruby)

export default class extends Controller {
  static targets = ["textarea", "highlight"]

  connect() {
    this.highlightTarget.classList.add("hljs")
    this.syncHighlight()
  }

  syncHighlight() {
    const code = this.textareaTarget.value
    const result = hljs.highlight(code, { language: "ruby" })
    this.highlightTarget.innerHTML = result.value + "\n"
    this.syncScroll()
  }

  syncScroll() {
    this.highlightTarget.scrollTop = this.textareaTarget.scrollTop
    this.highlightTarget.scrollLeft = this.textareaTarget.scrollLeft
  }
}
