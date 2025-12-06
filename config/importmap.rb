# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Charting
pin "highcharts", to: "https://cdn.jsdelivr.net/npm/highcharts@11.4.0/es-modules/masters/highcharts.src.min.js"
