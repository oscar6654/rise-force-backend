import { Controller } from "@hotwired/stimulus"

// Add/remove rows in a nested form (e.g. promo mechanic lines). A hidden
// <template> holds the blank row markup with NEW_RECORD placeholders that are
// swapped for a unique index on insert.
export default class extends Controller {
  static targets = ["template", "rows"]

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime())
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
  }

  // Removes an unsaved row, or marks a persisted row for destruction.
  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-nested-row]")
    const destroyField = row.querySelector("input[name*='_destroy']")
    if (destroyField) {
      destroyField.value = "1"
      row.style.display = "none"
    } else {
      row.remove()
    }
  }
}
