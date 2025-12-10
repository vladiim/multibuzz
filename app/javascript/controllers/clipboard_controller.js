import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button", "label"]

  async copy() {
    const text = this.sourceTarget.textContent

    try {
      await navigator.clipboard.writeText(text)
      this.showCopied()
    } catch (err) {
      // Fallback for older browsers
      this.fallbackCopy(text)
    }
  }

  fallbackCopy(text) {
    const textArea = document.createElement("textarea")
    textArea.value = text
    textArea.style.position = "fixed"
    textArea.style.left = "-999999px"
    document.body.appendChild(textArea)
    textArea.select()

    try {
      document.execCommand("copy")
      this.showCopied()
    } catch (err) {
      console.error("Copy failed", err)
    }

    document.body.removeChild(textArea)
  }

  showCopied() {
    const originalText = this.labelTarget.textContent
    this.labelTarget.textContent = "Copied!"
    this.buttonTarget.classList.add("bg-green-600")
    this.buttonTarget.classList.remove("bg-indigo-600", "hover:bg-indigo-500")

    setTimeout(() => {
      this.labelTarget.textContent = originalText
      this.buttonTarget.classList.remove("bg-green-600")
      this.buttonTarget.classList.add("bg-indigo-600", "hover:bg-indigo-500")
    }, 2000)
  }
}
