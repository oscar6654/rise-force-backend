import { Controller } from "@hotwired/stimulus"

// Shows only the line fields relevant to the selected promo mechanic. Each
// field cell tags itself with data-mechanics="a b c"; cells with no tag are
// always shown. A MutationObserver re-applies when new lines are added.
export default class extends Controller {
  static targets = ["type"]

  connect() {
    this.refresh()
    this.observer = new MutationObserver(() => this.refresh())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  refresh() {
    const mechanic = this.typeTarget.value
    this.element.querySelectorAll("[data-mechanics]").forEach((cell) => {
      const list = cell.dataset.mechanics.split(" ").filter(Boolean)
      cell.classList.toggle("hidden", list.length > 0 && !list.includes(mechanic))
    })
  }
}
