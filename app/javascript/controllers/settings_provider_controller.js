import { Controller } from "@hotwired/stimulus"

// Shows only the field group relevant to the chosen email provider, so the
// Email tab isn't cluttered with both Mailgun and SMTP fields at once.
// <div data-controller="settings-provider">
//   <select data-settings-provider-target="select" data-action="settings-provider#change">
//   <div data-settings-provider-target="group" data-provider="mailgun">…</div>
//   <div data-settings-provider-target="group" data-provider="smtp">…</div>
export default class extends Controller {
  static targets = ["select", "group"]

  connect() { this.change() }

  change() {
    const choice = this.selectTarget.value // auto | mailgun | smtp
    this.groupTargets.forEach(group => {
      const provider = group.dataset.provider
      // "auto" shows both so either path can be configured.
      group.hidden = !(choice === "auto" || choice === provider)
    })
  }
}
