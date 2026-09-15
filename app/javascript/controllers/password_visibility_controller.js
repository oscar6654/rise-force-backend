import { Controller } from "@hotwired/stimulus"

// Reveals/masks a sensitive settings value. The input holds the real saved
// value (masked by default) so re-saving the form keeps the secret intact.
// <div data-controller="password-visibility">
//   <input data-password-visibility-target="input" type="password">
//   <button data-action="password-visibility#toggle" data-password-visibility-target="label">Show</button>
export default class extends Controller {
  static targets = ["input", "label"]

  toggle() {
    const revealed = this.inputTarget.type === "text"
    this.inputTarget.type = revealed ? "password" : "text"
    if (this.hasLabelTarget) this.labelTarget.textContent = revealed ? "Show" : "Hide"
  }
}
