module DashboardHelper
  ATTRIBUTION_MODEL_DESCRIPTIONS = {
    "first_touch" => "100% credit to the first marketing touchpoint",
    "last_touch" => "100% credit to the last touchpoint before conversion",
    "linear" => "Equal credit distributed across all touchpoints",
    "time_decay" => "More credit to touchpoints closer to conversion",
    "u_shaped" => "40% to first, 40% to last, 20% split among middle",
    "participation" => "100% credit to every touchpoint (totals > 100%)"
  }.freeze

  METRIC_FORMATTERS = {
    currency: ->(v, h) { h.number_to_currency(v, precision: 0) },
    percentage: ->(v, _) { "#{v}%" },
    number: ->(v, h) { h.number_with_delimiter(v) }
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

  def chart_or_empty(data:, empty_message: "No data for the selected period", &block)
    if data.blank?
      content_tag(:div, empty_message, class: "h-64 flex items-center justify-center text-gray-500")
    else
      capture(&block)
    end
  end

  def hidden_filter_params(except: [])
    params_to_preserve = @filter_params.except(*Array(except))

    safe_join(params_to_preserve.flat_map { |key, value| hidden_inputs_for(key, value) })
  end

  private

  def hidden_inputs_for(key, value)
    case value
    when Array
      value.map { |v| hidden_input_tag(key, v, array: true) }
    when Hash
      value.map { |k, v| tag.input(type: "hidden", name: "#{key}[#{k}]", value: v) }
    else
      [tag.input(type: "hidden", name: key, value: value)]
    end
  end

  def hidden_input_tag(key, value, array: false)
    name = array ? "#{key}[]" : key
    actual_value = value.respond_to?(:prefix_id) ? value.prefix_id : value
    tag.input(type: "hidden", name: name, value: actual_value)
  end
end
