# frozen_string_literal: true

module Demo
  class DataGeneratorService
    DEMO_CHANNELS = [
      Channels::PAID_SEARCH,
      Channels::ORGANIC_SEARCH,
      Channels::PAID_SOCIAL,
      Channels::EMAIL,
      Channels::DIRECT
    ].freeze

    CHANNEL_WEIGHTS = {
      Channels::PAID_SEARCH => 0.30,
      Channels::ORGANIC_SEARCH => 0.25,
      Channels::PAID_SOCIAL => 0.20,
      Channels::EMAIL => 0.15,
      Channels::DIRECT => 0.10
    }.freeze

    REVENUE_RANGE = (29..299).freeze
    SESSION_COUNT = 500
    CONVERSION_COUNT = 50

    def initialize(seed: nil)
      @random = seed ? Random.new(seed) : Random.new
    end

    def call
      generate_data
    end

    private

    attr_reader :random

    def generate_data
      sessions = generate_sessions
      conversions = generate_conversions(sessions)
      channel_breakdown = calculate_channel_breakdown(sessions, conversions)
      sample_journey = generate_sample_journey(sessions, conversions)

      {
        sessions: sessions,
        conversions: conversions,
        channel_breakdown: channel_breakdown,
        sample_journey: sample_journey,
        summary: generate_summary(conversions, channel_breakdown)
      }
    end

    def generate_sessions
      SESSION_COUNT.times.map do |i|
        {
          id: "sess_demo_#{i}",
          visitor_id: "vis_demo_#{i % 100}",
          channel: weighted_random_channel,
          started_at: random_date_within_30_days,
          utm_source: random_utm_source,
          utm_medium: random_utm_medium
        }
      end.sort_by { |s| s[:started_at] }
    end

    def generate_conversions(sessions)
      converting_visitors = sessions.map { |s| s[:visitor_id] }.uniq.sample(CONVERSION_COUNT, random: random)

      converting_visitors.map.with_index do |visitor_id, i|
        visitor_sessions = sessions.select { |s| s[:visitor_id] == visitor_id }
        conversion_session = visitor_sessions.last

        {
          id: "conv_demo_#{i}",
          visitor_id: visitor_id,
          session_id: conversion_session[:id],
          revenue: random.rand(REVENUE_RANGE),
          converted_at: conversion_session[:started_at] + random.rand(1..60).minutes,
          touchpoints: visitor_sessions.map { |s| s[:channel] }
        }
      end
    end

    def calculate_channel_breakdown(sessions, conversions)
      channel_credits = DEMO_CHANNELS.each_with_object({}) { |c, h| h[c] = 0.0 }
      channel_revenue = DEMO_CHANNELS.each_with_object({}) { |c, h| h[c] = 0.0 }

      conversions.each do |conversion|
        touchpoints = conversion[:touchpoints]
        credit_per_touchpoint = 1.0 / touchpoints.size
        revenue_per_touchpoint = conversion[:revenue].to_f / touchpoints.size

        touchpoints.each do |channel|
          channel_credits[channel] += credit_per_touchpoint
          channel_revenue[channel] += revenue_per_touchpoint
        end
      end

      total_credit = channel_credits.values.sum

      DEMO_CHANNELS.map do |channel|
        {
          channel: channel,
          credit: total_credit.positive? ? channel_credits[channel] / total_credit : 0.0,
          revenue_credit: channel_revenue[channel].round(2),
          session_count: sessions.count { |s| s[:channel] == channel }
        }
      end.sort_by { |b| -b[:credit] }
    end

    def generate_sample_journey(sessions, conversions)
      conversion = conversions.find { |c| c[:touchpoints].size >= 3 } || conversions.first
      return { touchpoints: [], conversion: nil } unless conversion

      visitor_sessions = sessions.select { |s| s[:visitor_id] == conversion[:visitor_id] }

      {
        touchpoints: visitor_sessions.map do |session|
          {
            channel: session[:channel],
            date: session[:started_at].strftime("%b %d"),
            day_number: (session[:started_at].to_date - 30.days.ago.to_date).to_i
          }
        end,
        conversion: {
          revenue: conversion[:revenue],
          date: conversion[:converted_at].strftime("%b %d")
        }
      }
    end

    def generate_summary(conversions, channel_breakdown)
      {
        total_conversions: conversions.size,
        total_revenue: conversions.sum { |c| c[:revenue] },
        top_channel: channel_breakdown.first&.dig(:channel),
        average_touchpoints: (conversions.sum { |c| c[:touchpoints].size }.to_f / conversions.size).round(1)
      }
    end

    def weighted_random_channel
      roll = random.rand
      cumulative = 0.0

      CHANNEL_WEIGHTS.each do |channel, weight|
        cumulative += weight
        return channel if roll < cumulative
      end

      DEMO_CHANNELS.last
    end

    def random_date_within_30_days
      30.days.ago + random.rand(30).days + random.rand(24).hours
    end

    def random_utm_source
      sources = %w[google facebook email linkedin twitter]
      sources.sample(random: random)
    end

    def random_utm_medium
      mediums = %w[cpc organic social email referral]
      mediums.sample(random: random)
    end
  end
end
