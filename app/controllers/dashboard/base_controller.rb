module Dashboard
  class BaseController < ApplicationController
    before_action :require_login
    helper_method :view_mode, :test_mode?

    VALID_VIEW_MODES = %w[production test].freeze
    DEFAULT_VIEW_MODE = "production"
    PRESET_DATE_RANGES = %w[7d 30d 90d].freeze
    DEFAULT_DATE_RANGE = "30d"
    VALID_METRICS = %w[conversions revenue aov avg_days avg_channels avg_visits].freeze
    DEFAULT_METRIC = "conversions"

    private

    def selected_attribution_models
      @selected_attribution_models ||= find_attribution_models.presence || [default_attribution_model]
    end

    def find_attribution_models
      return [] unless params[:models].present?

      Array(params[:models]).filter_map do |prefix_id|
        current_account.attribution_models.active.find_by_prefix_id(prefix_id)
      end.first(2)
    end

    def default_attribution_model
      current_account.attribution_models.active.find_by(is_default: true) ||
        current_account.attribution_models.active.first
    end

    def date_range_param
      return params[:date_range] if PRESET_DATE_RANGES.include?(params[:date_range])
      return { start_date: params[:start_date], end_date: params[:end_date] } if custom_date_range?

      DEFAULT_DATE_RANGE
    end

    def custom_date_range?
      params[:start_date].present? && params[:end_date].present?
    end

    def channels_param
      return Channels::ALL if params[:channels].blank?

      channels = normalize_channels_param
      valid = channels & Channels::ALL
      valid.presence || Channels::ALL
    end

    def normalize_channels_param
      case params[:channels]
      when Array then params[:channels].map(&:strip)
      when String then params[:channels].split(",").map(&:strip)
      else []
      end
    end

    def journey_position_param
      value = params[:journey_position]
      return value if AttributionAlgorithms::JOURNEY_POSITIONS.include?(value)

      AttributionAlgorithms::DEFAULT_JOURNEY_POSITION
    end

    def metric_param
      VALID_METRICS.include?(params[:metric]) ? params[:metric] : DEFAULT_METRIC
    end

    def filter_params
      {
        date_range: date_range_param,
        models: selected_attribution_models,
        channels: channels_param,
        journey_position: journey_position_param,
        metric: metric_param,
        funnel: funnel_param,
        conversion_filters: conversion_filters_param,
        breakdown_dimension: breakdown_dimension_param
      }
    end

    def funnel_param
      params[:funnel].presence
    end

    def conversion_filters_param
      @conversion_filters_param ||= parse_conversion_filters
    end

    def parse_conversion_filters
      return [] unless params[:conversion_filters].present?

      params[:conversion_filters].map do |filter|
        {
          field: filter[:field].to_s,
          operator: filter[:operator].to_s,
          values: Array(filter[:values]).map(&:to_s)
        }
      end.select { |f| f[:field].present? && f[:values].any? }
    end

    def breakdown_dimension_param
      params[:breakdown_dimension].presence || "conversion_type"
    end

    # View mode toggle (like Stripe's test/live mode)
    def view_mode
      session[:view_mode].presence_in(VALID_VIEW_MODES) || DEFAULT_VIEW_MODE
    end

    def test_mode?
      view_mode == "test"
    end

    def environment_scope
      test_mode? ? :test_data : :production
    end

    # Scoped accessors for dashboard queries
    def scoped_visitors
      current_account.visitors.send(environment_scope)
    end

    def scoped_sessions
      current_account.sessions.send(environment_scope)
    end

    def scoped_events
      current_account.events.send(environment_scope)
    end

    def scoped_conversions
      current_account.conversions.send(environment_scope)
    end

    def scoped_attribution_credits
      current_account.attribution_credits.send(environment_scope)
    end
  end
end
