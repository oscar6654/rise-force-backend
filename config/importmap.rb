# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# NOTE: Tom Select is loaded as a self-contained global via a plain <script>
# in the layout (public/tom-select.min.js), not through importmap — its ESM
# build pulls sub-dependencies from absolute CDN paths that can't resolve offline.
pin_all_from "app/javascript/controllers", under: "controllers"
