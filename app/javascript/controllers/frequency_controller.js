import { Controller } from "@hotwired/stimulus"

// Keeps the week-pattern consistent with the visit frequency: F4 (weekly) can
// only be "every week", so the 1&3 / 2&4 options are disabled and the value is
// forced. F2 (twice a month) must use a fortnightly pattern.
export default class extends Controller {
  static targets = ["frequency", "pattern"]

  connect() {
    this.sync()
  }

  sync() {
    const isF4 = this.frequencyTarget.value === "f4"
    Array.from(this.patternTarget.options).forEach((opt) => {
      if (opt.value === "every_week") {
        opt.disabled = !isF4 ? true : false
      } else {
        opt.disabled = isF4
      }
    })

    if (isF4) {
      this.patternTarget.value = "every_week"
    } else if (this.patternTarget.value === "every_week") {
      // F2 needs a fortnightly pattern — default to weeks 1 & 3.
      this.patternTarget.value = "weeks_1_3"
    }
  }
}
