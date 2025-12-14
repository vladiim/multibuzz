import { Controller } from "@hotwired/stimulus"
import hljs from "highlight.js/lib/core"
import ruby from "highlight.js/lib/languages/ruby"
import bash from "highlight.js/lib/languages/bash"
import python from "highlight.js/lib/languages/python"
import php from "highlight.js/lib/languages/php"
import javascript from "highlight.js/lib/languages/javascript"

hljs.registerLanguage("ruby", ruby)
hljs.registerLanguage("bash", bash)
hljs.registerLanguage("python", python)
hljs.registerLanguage("php", php)
hljs.registerLanguage("javascript", javascript)

export default class extends Controller {
  static values = { language: { type: String, default: "ruby" } }

  connect() {
    this.highlight()
  }

  highlight() {
    const code = this.element.textContent
    this.element.innerHTML = hljs.highlight(code, { language: this.languageValue }).value
  }
}
