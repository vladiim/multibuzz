import { Controller } from "@hotwired/stimulus"
import Highcharts from "highcharts"

// Channel color palette
const CHANNEL_COLORS = {
  paid_search: "#6366F1",     // indigo
  organic_search: "#10B981",  // emerald
  paid_social: "#F59E0B",     // amber
  organic_social: "#84CC16",  // lime
  email: "#EC4899",           // pink
  display: "#8B5CF6",         // violet
  affiliate: "#14B8A6",       // teal
  referral: "#F97316",        // orange
  video: "#EF4444",           // red
  direct: "#6B7280",          // gray
  other: "#9CA3AF"            // gray-400
}

export default class extends Controller {
  static values = {
    type: String,
    data: String,
    metric: { type: String, default: "credits" },
    drilldown: { type: Boolean, default: false },
    campaigns: String
  }

  connect() {
    this.renderChart()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }

  renderChart() {
    switch (this.typeValue) {
      case "bar":
        this.renderBarChart()
        break
      case "stacked-bar":
        this.renderStackedBarChart()
        break
      case "line":
        this.renderLineChart()
        break
      default:
        console.warn(`Unknown chart type: ${this.typeValue}`)
    }
  }

  renderBarChart() {
    const data = this.parseData()
    if (!Array.isArray(data)) return

    const campaigns = this.parseCampaigns()
    const metric = this.metricValue
    const isRevenue = metric === "revenue"
    const hasDrilldown = this.drilldownValue && Object.keys(campaigns).length > 0

    const categories = data.map(d => this.formatChannelName(d.channel))
    const channelIds = data.map(d => d.channel)
    const values = data.map(d => d[metric])
    const colors = data.map(d => CHANNEL_COLORS[d.channel] || CHANNEL_COLORS.other)

    const chartConfig = {
      chart: {
        type: "bar",
        events: hasDrilldown ? {
          click: (e) => {
            if (this.isDrilledDown) {
              this.drillUp()
            }
          }
        } : {}
      },
      title: { text: null },
      xAxis: {
        categories: categories,
        labels: { style: { fontSize: "12px" } }
      },
      yAxis: {
        title: { text: isRevenue ? "Revenue ($)" : "Conversions" },
        min: 0
      },
      legend: { enabled: false },
      tooltip: {
        formatter: function() {
          const val = isRevenue ? `$${Highcharts.numberFormat(this.y, 0)}` : this.y
          return `<b>${this.x}</b><br/>${val}`
        }
      },
      plotOptions: {
        bar: {
          colorByPoint: true,
          colors: colors,
          cursor: hasDrilldown ? "pointer" : "default",
          dataLabels: {
            enabled: true,
            format: isRevenue ? "${y:,.0f}" : "{y}"
          },
          point: {
            events: hasDrilldown ? {
              click: (e) => {
                const channelId = channelIds[e.point.index]
                this.drillDown(channelId, isRevenue)
              }
            } : {}
          }
        }
      },
      series: [{
        name: isRevenue ? "Revenue" : "Conversions",
        data: values
      }],
      credits: { enabled: false }
    }

    this.chart = Highcharts.chart(this.element, chartConfig)
    this.originalData = data
    this.isDrilledDown = false
  }

  drillDown(channelId, isRevenue) {
    const allCampaigns = this.parseCampaigns()
    const campaigns = allCampaigns[channelId]
    if (!campaigns || campaigns.length === 0) return

    const metric = isRevenue ? "revenue" : "conversions"
    const categories = campaigns.map(c => c.name)
    const values = campaigns.map(c => c[metric])

    this.chart.update({
      xAxis: { categories: categories },
      series: [{ data: values }],
      subtitle: { text: "← Click anywhere to go back" }
    })

    this.isDrilledDown = true
  }

  drillUp() {
    const data = this.originalData
    const metric = this.metricValue
    const isRevenue = metric === "revenue"

    const categories = data.map(d => this.formatChannelName(d.channel))
    const values = data.map(d => d[metric])

    this.chart.update({
      xAxis: { categories: categories },
      series: [{ data: values }],
      subtitle: { text: null }
    })

    this.isDrilledDown = false
  }

  renderLineChart() {
    const data = this.parseData()
    if (!data) return

    const dates = data.dates || []
    const seriesData = data.series || []

    const series = seriesData.map(s => ({
      name: this.formatChannelName(s.channel),
      color: CHANNEL_COLORS[s.channel] || CHANNEL_COLORS.other,
      data: s.data
    }))

    this.chart = Highcharts.chart(this.element, {
      chart: { type: "line" },
      title: { text: null },
      xAxis: {
        categories: dates.map(d => {
          const date = new Date(d)
          return `${date.getMonth() + 1}/${date.getDate()}`
        }),
        labels: {
          step: 5,
          style: { fontSize: "11px" }
        }
      },
      yAxis: {
        title: { text: "Conversions" },
        min: 0
      },
      legend: {
        align: "right",
        verticalAlign: "top",
        layout: "horizontal",
        itemStyle: { fontSize: "11px" }
      },
      plotOptions: {
        line: {
          marker: { enabled: false }
        }
      },
      series: series,
      credits: { enabled: false }
    })
  }

  renderStackedBarChart() {
    const stages = this.parseData()
    if (!Array.isArray(stages) || stages.length === 0) return

    const categories = stages.map(s => s.stage)

    // Get all channels from first stage
    const channels = Object.keys(stages[0].by_channel || {})

    // Build series for each channel
    const series = channels.map(channel => ({
      name: this.formatChannelName(channel),
      color: CHANNEL_COLORS[channel] || CHANNEL_COLORS.other,
      data: stages.map(stage => stage.by_channel[channel] || 0)
    }))

    this.chart = Highcharts.chart(this.element, {
      chart: { type: "bar" },
      title: { text: null },
      xAxis: {
        categories: categories,
        labels: { style: { fontSize: "12px" } }
      },
      yAxis: {
        min: 0,
        title: { text: "Events" },
        stackLabels: { enabled: true }
      },
      legend: {
        align: "right",
        verticalAlign: "top",
        layout: "vertical",
        itemStyle: { fontSize: "11px" }
      },
      plotOptions: {
        series: { stacking: "normal" }
      },
      series: series,
      credits: { enabled: false }
    })
  }

  parseData() {
    try {
      return this.dataValue ? JSON.parse(this.dataValue) : null
    } catch (e) {
      console.warn("Failed to parse chart data:", e)
      return null
    }
  }

  parseCampaigns() {
    try {
      return this.campaignsValue ? JSON.parse(this.campaignsValue) : {}
    } catch (e) {
      console.warn("Failed to parse campaigns data:", e)
      return {}
    }
  }

  formatChannelName(channel) {
    return channel
      .split("_")
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(" ")
  }
}
