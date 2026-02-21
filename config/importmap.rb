# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Charting
pin "highcharts", to: "https://cdn.jsdelivr.net/npm/highcharts@11.4.0/es-modules/masters/highcharts.src.min.js"

# Syntax highlighting
pin "highlight.js/lib/core", to: "https://esm.sh/highlight.js@11.9.0/lib/core"
pin "highlight.js/lib/languages/ruby", to: "https://esm.sh/highlight.js@11.9.0/lib/languages/ruby"
pin "highlight.js/lib/languages/bash", to: "https://esm.sh/highlight.js@11.9.0/lib/languages/bash"
pin "highlight.js/lib/languages/python", to: "https://esm.sh/highlight.js@11.9.0/lib/languages/python"
pin "highlight.js/lib/languages/php", to: "https://esm.sh/highlight.js@11.9.0/lib/languages/php"
pin "highlight.js/lib/languages/javascript", to: "https://esm.sh/highlight.js@11.9.0/lib/languages/javascript"
