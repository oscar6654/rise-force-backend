import { Controller } from "@hotwired/stimulus"
// TomSelect is loaded as a self-contained global (public/tom-select.min.js)
// because its ESM build pulls sub-deps from absolute CDN paths.

// Turns a native <select> into a searchable dropdown. Use on large lists
// (sellers, SKUs, stores, routes). Add data-controller="tom-select".
// Options:
//   data-tom-select-max-options-value  – cap rendered options (default 1000)
//   data-tom-select-placeholder-value  – placeholder text
export default class extends Controller {
  static values = {
    maxOptions: { type: Number, default: 1000 },
    placeholder: String,
    create: { type: Boolean, default: false }
  }

  connect() {
    const TomSelect = window.TomSelect
    if (!TomSelect) return // script not loaded yet; leave the native select

    const isMultiple = this.element.multiple
    this.select = new TomSelect(this.element, {
      maxOptions: this.maxOptionsValue,
      placeholder: this.placeholderValue || this.element.dataset.placeholder,
      plugins: isMultiple ? ["remove_button"] : [],
      allowEmptyOption: true,
      // create: true lets the user add a value that isn't in the list yet
      // (used for flexible tier / store-category masters).
      create: this.createValue,
      createOnBlur: this.createValue,
      // Keep the browser-native selected value in sync for form posts.
      onInitialize() { this.sync() }
    })
  }

  disconnect() {
    // Turbo caches pages — tear down so we don't double-init on restore.
    if (this.select) {
      this.select.destroy()
      this.select = null
    }
  }
}
