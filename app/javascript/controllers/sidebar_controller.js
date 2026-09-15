import { Controller } from "@hotwired/stimulus"

// Toggles the sidebar as an overlay on small screens. On md+ the sidebar is
// always visible (md:flex), so toggling only matters on mobile.
export default class extends Controller {
  static targets = ["panel", "backdrop"]

  toggle() {
    const hidden = this.panelTarget.classList.contains("hidden")
    hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    this.panelTarget.classList.add("flex")
    this.backdropTarget.classList.remove("hidden")
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.panelTarget.classList.remove("flex")
    this.backdropTarget.classList.add("hidden")
  }
}
