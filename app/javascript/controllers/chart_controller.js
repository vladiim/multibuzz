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
  ai: "#06B6D4",              // cyan
  direct: "#6B7280",          // gray
  other: "#9CA3AF"            // gray-400
}

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    type: String,
    data: String,
    metric: { type: String, default: "credits" },
    drilldown: { type: Boolean, default: false },
    campaigns: String,
    logScale: { type: Boolean, default: false }
  }

  connect() {
    this.renderChart()
  }

  get chartElement() {
    return this.hasCanvasTarget ? this.canvasTarget : this.element
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }

  toggleLogScale() {
    this.logScaleValue = !this.logScaleValue
    this.renderChart()
  }

  renderChart() {
    if (this.chart) {
      this.chart.destroy()
    }

    switch (this.typeValue) {
      case "bar":
        this.renderBarChart()
        break
      case "stacked-bar":
        this.renderStackedBarChart()
        break
      case "funnel":
        this.renderFunnelChart()
        break
      case "line":
        this.renderLineChart()
        break
      case "spend-trend":
        this.renderSpendTrendChart()
        break
      default:
        console.warn(`Unknown chart type: ${this.typeValue}`)
    }
  }

  renderSpendTrendChart() {
    const data = this.parseData()
    if (!Array.isArray(data) || data.length === 0) return

    const dates = data.map(d => {
      const date = new Date(d.date)
      return `${date.getMonth() + 1}/${date.getDate()}`
    })

    this.chart = Highcharts.chart(this.chartElement, {
      chart: { type: "column" },
      title: { text: null },
      xAxis: {
        categories: dates,
        labels: { step: Math.max(1, Math.floor(dates.length / 10)), style: { fontSize: "11px" } }
      },
      yAxis: [{
        title: { text: "Spend ($)" },
        min: 0
      }, {
        title: { text: "ROAS", style: { color: "#6366F1" } },
        labels: { format: "{value}x", style: { color: "#6366F1" } },
        min: 0,
        opposite: true
      }],
      legend: {
        align: "right",
        verticalAlign: "top",
        layout: "horizontal",
        itemStyle: { fontSize: "11px" }
      },
      tooltip: {
        shared: true,
        formatter: function() {
          let html = `<b>${this.x}</b><br/>`
          this.points.forEach(point => {
            const val = point.series.yAxis.options.index === 1
              ? `${Highcharts.numberFormat(point.y, 2)}x`
              : `$${Highcharts.numberFormat(point.y, 0)}`
            html += `<span style="color:${point.color}">●</span> ${point.series.name}: ${val}<br/>`
          })
          return html
        }
      },
      plotOptions: {
        column: { borderRadius: 2 }
      },
      series: [{
        name: "Spend",
        type: "column",
        color: "#E5E7EB",
        data: data.map(d => d.spend),
        yAxis: 0
      }, {
        name: "ROAS",
        type: "line",
        color: "#6366F1",
        data: data.map(d => d.roas || 0),
        yAxis: 1,
        marker: { enabled: false },
        lineWidth: 2
      }],
      credits: { enabled: false }
    })
  }

  renderBarChart() {
    const data = this.parseData()
    if (!Array.isArray(data)) return

    const campaigns = this.parseCampaigns()
    const metric = this.metricValue
    const metricConfig = this.getMetricConfig(metric)
    const hasDrilldown = this.drilldownValue && Object.keys(campaigns).length > 0 && metricConfig.drilldownable

    const categories = data.map(d => this.formatChannelName(d.channel))
    const channelIds = data.map(d => d.channel)
    const values = data.map(d => d[metricConfig.dataKey] || 0)
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
        title: { text: metricConfig.yAxisTitle },
        min: 0
      },
      legend: { enabled: false },
      tooltip: {
        formatter: function() {
          return `<b>${this.x}</b><br/>${metricConfig.formatValue(this.y)}`
        }
      },
      plotOptions: {
        bar: {
          colorByPoint: true,
          colors: colors,
          cursor: hasDrilldown ? "pointer" : "default",
          dataLabels: {
            enabled: true,
            format: metricConfig.dataLabelFormat
          },
          point: {
            events: hasDrilldown ? {
              click: (e) => {
                const channelId = channelIds[e.point.index]
                this.drillDown(channelId, metric === "revenue")
              }
            } : {}
          }
        }
      },
      series: [{
        name: metricConfig.seriesName,
        data: values
      }],
      credits: { enabled: false }
    }

    this.chart = Highcharts.chart(this.chartElement, chartConfig)
    this.originalData = data
    this.isDrilledDown = false
  }

  getMetricConfig(metric) {
    const configs = {
      revenue: {
        dataKey: "revenue",
        yAxisTitle: "Revenue ($)",
        seriesName: "Revenue",
        dataLabelFormat: "${y:,.0f}",
        formatValue: (y) => `$${Highcharts.numberFormat(y, 0)}`,
        drilldownable: true
      },
      aov: {
        dataKey: "aov",
        yAxisTitle: "Avg Order Value ($)",
        seriesName: "AOV",
        dataLabelFormat: "${y:,.0f}",
        formatValue: (y) => `$${Highcharts.numberFormat(y, 2)}`,
        drilldownable: false
      },
      clv: {
        dataKey: "clv",
        yAxisTitle: "Customer Lifetime Value ($)",
        seriesName: "CLV",
        dataLabelFormat: "${y:,.0f}",
        formatValue: (y) => `$${Highcharts.numberFormat(y, 2)}`,
        drilldownable: false
      },
      credits: {
        dataKey: "credits",
        yAxisTitle: "Conversions",
        seriesName: "Conversions",
        dataLabelFormat: "{y:.1f}",
        formatValue: (y) => Highcharts.numberFormat(y, 1),
        drilldownable: true
      },
      avg_channels: {
        dataKey: "avg_channels",
        yAxisTitle: "Avg Channels",
        seriesName: "Avg Channels",
        dataLabelFormat: "{y:.1f}",
        formatValue: (y) => Highcharts.numberFormat(y, 1),
        drilldownable: false
      },
      avg_visits: {
        dataKey: "avg_visits",
        yAxisTitle: "Avg Visits",
        seriesName: "Avg Visits",
        dataLabelFormat: "{y:.1f}",
        formatValue: (y) => Highcharts.numberFormat(y, 1),
        drilldownable: false
      },
      avg_days: {
        dataKey: "avg_days",
        yAxisTitle: "Avg Days",
        seriesName: "Avg Days",
        dataLabelFormat: "{y:.1f}",
        formatValue: (y) => Highcharts.numberFormat(y, 1),
        drilldownable: false
      }
    }
    return configs[metric] || configs.credits
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
    const metricConfig = this.getMetricConfig(metric)

    const categories = data.map(d => this.formatChannelName(d.channel))
    const values = data.map(d => d[metricConfig.dataKey] || 0)

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

    // Handle smiling curve format (months + series by channel)
    if (data.months && data.series) {
      this.renderSmilingCurve(data)
      return
    }

    const dates = data.dates || []
    const seriesData = data.series || []
    const metric = this.metricValue
    const metricConfig = this.getMetricConfig(metric)

    const series = seriesData.map(s => ({
      name: this.formatChannelName(s.channel),
      color: CHANNEL_COLORS[s.channel] || CHANNEL_COLORS.other,
      // Handle both old format (array of numbers) and new format (array of objects with metrics)
      // Note: typeof null === "object" in JS, so check null first to preserve gaps for Highcharts
      data: s.data.map(d => {
        if (d === null || d === undefined) return null
        return typeof d === "object" ? (d[metricConfig.dataKey] || 0) : d
      }),
      connectNulls: true
    }))

    this.chart = Highcharts.chart(this.chartElement, {
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
        title: { text: metricConfig.yAxisTitle },
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

  renderSmilingCurve(data) {
    const categories = data.months.map(m => `M${m}`)

    // Build series for each channel
    const series = data.series.map(s => ({
      name: this.formatChannelName(s.channel),
      color: CHANNEL_COLORS[s.channel] || CHANNEL_COLORS.other,
      data: s.data
    }))

    this.chart = Highcharts.chart(this.chartElement, {
      chart: { type: "line" },
      title: { text: null },
      xAxis: {
        categories: categories,
        labels: { style: { fontSize: "11px" } }
      },
      yAxis: {
        title: { text: "Revenue per Customer ($)" },
        min: 0
      },
      legend: {
        align: "right",
        verticalAlign: "top",
        layout: "horizontal",
        itemStyle: { fontSize: "11px" }
      },
      tooltip: {
        shared: true,
        formatter: function() {
          let html = `<b>Month ${this.x.replace("M", "")}</b><br/>`
          this.points.forEach(point => {
            html += `<span style="color:${point.color}">●</span> ${point.series.name}: $${Highcharts.numberFormat(point.y, 2)}<br/>`
          })
          return html
        }
      },
      plotOptions: {
        line: {
          marker: { enabled: true, radius: 3 },
          lineWidth: 2
        }
      },
      series: series,
      credits: { enabled: false }
    })
  }

  renderStackedBarChart() {
    const data = this.parseData()
    if (!Array.isArray(data) || data.length === 0) return

    // Check if data has by_channel breakdown (conversion dimension chart)
    const hasChannelBreakdown = data[0]?.by_channel !== undefined

    if (hasChannelBreakdown) {
      this.renderConversionsByChannelChart(data)
    } else {
      this.renderFunnelStackedChart(data)
    }
  }

  renderConversionsByChannelChart(data) {
    const categories = data.map(d => d.channel) // conversion name/type
    const metric = this.metricValue
    const metricConfig = this.getMetricConfig(metric)
    const isAverageMetric = ["avg_channels", "avg_visits", "avg_days", "aov"].includes(metric)

    let series
    if (isAverageMetric) {
      // Averages don't stack — show single bar per conversion type
      series = [{
        name: metricConfig.seriesName,
        color: "#6366F1",
        data: data.map(d => d[metricConfig.dataKey] || 0)
      }]
    } else {
      // Get all unique channels across all rows
      const allChannels = [...new Set(
        data.flatMap(d => (d.by_channel || []).map(c => c.channel))
      )]

      // Build stacked series for each channel
      series = allChannels.map(channel => ({
        name: this.formatChannelName(channel),
        color: CHANNEL_COLORS[channel] || CHANNEL_COLORS.other,
        data: data.map(d => {
          const channelData = (d.by_channel || []).find(c => c.channel === channel)
          return channelData ? (channelData[metricConfig.dataKey] || 0) : 0
        })
      }))
    }

    this.chart = Highcharts.chart(this.chartElement, {
      chart: { type: "bar" },
      title: { text: null },
      xAxis: {
        categories: categories,
        labels: { style: { fontSize: "12px" } }
      },
      yAxis: {
        min: 0,
        title: { text: metricConfig.yAxisTitle },
        stackLabels: {
          enabled: true,
          format: (metric === "revenue" || metric === "aov") ? "${total:,.0f}" : "{total:.1f}"
        }
      },
      legend: {
        align: "center",
        verticalAlign: "top",
        layout: "horizontal",
        itemStyle: { fontSize: "11px" }
      },
      tooltip: {
        formatter: function() {
          let html = `<b>${this.x}</b><br/>`
          let total = 0
          const yAxisTitle = this.series.chart.options.yAxis[0].title.text
          const isCurrency = yAxisTitle.includes("$")
          this.points.forEach(point => {
            total += point.y
            const formatted = isCurrency ? `$${Highcharts.numberFormat(point.y, 0)}` : Highcharts.numberFormat(point.y, 1)
            html += `<span style="color:${point.color}">●</span> ${point.series.name}: ${formatted}<br/>`
          })
          const totalFormatted = isCurrency ? `$${Highcharts.numberFormat(total, 0)}` : Highcharts.numberFormat(total, 1)
          html += `<b>Total: ${totalFormatted}</b>`
          return html
        },
        shared: true
      },
      plotOptions: {
        series: { stacking: isAverageMetric ? undefined : "normal" }
      },
      series: series,
      credits: { enabled: false }
    })
  }

  renderFunnelStackedChart(stages) {
    const categories = stages.map(s => s.stage)

    // Get all channels from first stage
    const channels = Object.keys(stages[0].by_channel || {})

    // Build series for each channel
    const series = channels.map(channel => ({
      name: this.formatChannelName(channel),
      color: CHANNEL_COLORS[channel] || CHANNEL_COLORS.other,
      data: stages.map(stage => stage.by_channel[channel] || 0)
    }))

    this.chart = Highcharts.chart(this.chartElement, {
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

  renderFunnelChart() {
    const stages = this.parseData()
    if (!Array.isArray(stages) || stages.length === 0) return

    const useLog = this.logScaleValue
    const categories = stages.map(s => s.stage)

    // Get channels with data (filter out zero-only channels)
    const allChannels = Object.keys(stages[0].by_channel || {})
    const channels = allChannels.filter(channel =>
      stages.some(stage => (stage.by_channel[channel] || 0) > 0)
    )

    // Build stacked column series for each channel
    const columnSeries = channels.map(channel => ({
      name: this.formatChannelName(channel),
      type: "column",
      color: CHANNEL_COLORS[channel] || CHANNEL_COLORS.other,
      data: stages.map(stage => stage.by_channel[channel] || 0),
      yAxis: 0
    }))

    // Build conversion rate line series
    const conversionRates = stages.map(s => s.conversion_rate)
    const lineSeries = {
      name: "Conversion Rate",
      type: "line",
      color: "#EF4444",
      data: conversionRates,
      yAxis: 1,
      marker: { enabled: true, radius: 6 },
      lineWidth: 3,
      dataLabels: {
        enabled: true,
        formatter: function() {
          return this.y ? `${this.y}%` : ""
        },
        style: { fontWeight: "bold", color: "#EF4444", textOutline: "none" }
      },
      zIndex: 10
    }

    // Stack totals for data labels
    const stageTotals = stages.map(s => s.total)

    this.chart = Highcharts.chart(this.chartElement, {
      chart: { type: "column" },
      title: { text: null },
      xAxis: {
        categories: categories,
        labels: {
          style: { fontSize: "12px" },
          rotation: -45
        }
      },
      yAxis: [{
        // Left Y-axis: Count
        type: useLog ? "logarithmic" : "linear",
        title: { text: useLog ? "Count (log scale)" : "Count" },
        min: useLog ? 1 : 0,
        stackLabels: {
          enabled: true,
          formatter: function() {
            return Highcharts.numberFormat(this.total, 0)
          },
          style: { fontWeight: "bold", color: "#374151" }
        }
      }, {
        // Right Y-axis: Conversion Rate %
        type: useLog ? "logarithmic" : "linear",
        title: {
          text: useLog ? "Conversion Rate (%, log)" : "Conversion Rate (%)",
          style: { color: "#EF4444" }
        },
        labels: {
          format: "{value}%",
          style: { color: "#EF4444" }
        },
        min: useLog ? 0.1 : 0,
        max: useLog ? 10000 : null,
        opposite: true
      }],
      legend: {
        align: "center",
        verticalAlign: "top",
        layout: "horizontal",
        itemStyle: { fontSize: "11px" }
      },
      plotOptions: {
        column: {
          stacking: "normal",
          dataLabels: { enabled: false }
        }
      },
      tooltip: {
        shared: true,
        formatter: function() {
          let html = `<b>${this.x}</b><br/>`
          let total = 0
          this.points.forEach(point => {
            if (point.series.type === "column") {
              total += point.y
              html += `<span style="color:${point.color}">●</span> ${point.series.name}: ${Highcharts.numberFormat(point.y, 0)}<br/>`
            }
          })
          html += `<b>Total: ${Highcharts.numberFormat(total, 0)}</b><br/>`
          const ratePoint = this.points.find(p => p.series.type === "line")
          if (ratePoint && ratePoint.y) {
            html += `<span style="color:#EF4444">●</span> Conversion Rate: ${ratePoint.y}%`
          }
          return html
        }
      },
      series: [...columnSeries, lineSeries],
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
