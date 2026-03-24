# frozen_string_literal: true

module SpendHelper
  MICRO_UNIT = AdSpendRecord::MICRO_UNIT

  TIMEZONE_OPTIONS = ActiveSupport::TimeZone.all
    .select { |tz| (tz.utc_offset % 3600).zero? }
    .map { |tz| [ tz.to_s, tz.utc_offset / 3600 ] }
    .sort_by(&:last)
    .freeze

  def format_spend(micros)
    return "$0.00" if micros.nil? || micros.zero?

    number_to_currency(micros.to_d / MICRO_UNIT, precision: 2)
  end

  def spend_channel_color(channel)
    Channels::COLORS.fetch(channel.to_s, Channels::COLORS[Channels::OTHER])
  end

  def spend_ctr(row)
    impressions = row[:impressions].to_i
    clicks = row[:clicks].to_i
    return "—" unless impressions.positive?

    "#{(clicks.to_f / impressions * 100).round(1)}%"
  end

  def spend_cpc(row)
    return "—" unless row[:cpc_micros]

    format_spend(row[:cpc_micros])
  end
end
