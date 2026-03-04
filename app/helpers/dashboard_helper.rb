# frozen_string_literal: true

module DashboardHelper
  ATTRIBUTION_MODEL_DESCRIPTIONS = {
    "first_touch" => "100% credit to the first marketing touchpoint",
    "last_touch" => "100% credit to the last touchpoint before conversion",
    "linear" => "Equal credit distributed across all touchpoints",
    "time_decay" => "More credit to touchpoints closer to conversion",
    "u_shaped" => "40% to first, 40% to last, 20% split among middle",
    "participation" => "100% credit to every touchpoint (totals > 100%)",
    "markov_chain" => "Data-driven credit based on channel removal effects",
    "shapley_value" => "Fair credit based on each channel's marginal contribution"
  }.freeze

  METRIC_FORMATTERS = {
    currency: ->(v, h) { h.number_to_currency(v, precision: 0) },
    percentage: ->(v, _) { "#{v}%" },
    number: ->(v, h) {
      formatted = v.is_a?(Float) ? v.round(1) : v
      h.number_with_delimiter(formatted)
    }
  }.freeze

  def attribution_model_description(algorithm)
    ATTRIBUTION_MODEL_DESCRIPTIONS[algorithm.to_s] || "Custom attribution model"
  end

  def percentage_change(current, prior)
    return nil if current.nil? || prior.nil? || prior.zero?

    ((current - prior).to_f / prior * 100).round(1)
  end

  def format_change(change)
    return content_tag(:span, "—", class: "ml-2 text-sm text-gray-400") if change.nil?

    css_class = change >= 0 ? "text-green-600" : "text-red-600"
    arrow = change >= 0 ? "↑" : "↓"
    content_tag(:span, "#{arrow} #{change.abs}%", class: "ml-2 text-sm #{css_class}")
  end

  def format_metric(value, type: :number)
    return "—" if value.nil?

    METRIC_FORMATTERS.fetch(type, METRIC_FORMATTERS[:number]).call(value, self)
  end

  def conversion_filters_label(filters)
    return "No filters" if filters.blank?

    count = filters.size
    count == 1 ? "1 filter" : "#{count} filters"
  end

  def format_time_gap(days)
    return "< 1 h" if days.nil? || days < (1.0 / 24)
    return pluralize(((days * 24).round), "hr") if days < 1
    return pluralize(days.round, "day") if days < 30

    pluralize((days / 30).round, "mo")
  end

  def chart_or_empty(data:, empty_message: "No data for the selected period", &block)
    if data.blank?
      content_tag(:div, empty_message, class: "h-64 flex items-center justify-center text-gray-500")
    else
      capture(&block)
    end
  end

  def cohort_cell_class(ltv, cohorts)
    return "" if ltv.nil?

    max_ltv = cohorts.flat_map { |c| c[:months].map { |m| m[:cumulative_ltv] } }.compact.max || 0
    return "" if max_ltv.zero?

    intensity = (ltv.to_f / max_ltv * 100).round
    case intensity
    when 80..100 then "bg-emerald-100 text-emerald-800"
    when 60..79 then "bg-emerald-50 text-emerald-700"
    when 40..59 then "bg-gray-50 text-gray-700"
    when 20..39 then "bg-amber-50 text-amber-700"
    else "bg-red-50 text-red-700"
    end
  end

  def hidden_filter_params(except: [])
    hidden_params_for(@filter_params.except(*Array(except)))
  end

  def hidden_params_for(params_hash)
    safe_join(params_hash.flat_map { |key, value| hidden_inputs_for(key, value) })
  end

  private

  def hidden_inputs_for(key, value)
    case value
    when Array
      value.flat_map.with_index { |v, i| hidden_inputs_for_array_element(key, v, i) }
    when Hash
      value.flat_map { |k, v| hidden_inputs_for("#{key}[#{k}]", v) }
    else
      [ hidden_input_tag(key, value) ]
    end
  end

  def hidden_inputs_for_array_element(key, value, index)
    return hidden_inputs_for("#{key}[#{index}]", value) if value.is_a?(Hash)

    [ hidden_input_tag(key, value, array: true) ]
  end

  def hidden_input_tag(key, value, array: false)
    name = array ? "#{key}[]" : key
    actual_value = value.respond_to?(:prefix_id) ? value.prefix_id : value
    tag.input(type: "hidden", name: name, value: actual_value)
  end
end
