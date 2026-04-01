import { Controller } from "@hotwired/stimulus"
import { renderRadar } from "helpers/radar_chart"

export default class extends Controller {
  static values = { dimensions: Object }

  connect() {
    renderRadar(this.element, this.dimensionsValue)
  }
}
