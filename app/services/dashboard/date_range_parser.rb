# frozen_string_literal: true

module Dashboard
  class DateRangeParser
    PRESETS = { "7d" => 7, "30d" => 30, "90d" => 90 }.freeze
    DEFAULT_DAYS = 30

    PARSERS = {
      Hash => ->(param) { [ Date.parse(param[:start_date]), Date.parse(param[:end_date]) ] },
      String => ->(param) { [ (PRESETS.fetch(param, DEFAULT_DAYS) - 1).days.ago.to_date, Date.current ] }
    }.freeze

    attr_reader :start_date, :end_date

    def initialize(date_range_param)
      @start_date, @end_date = parse(date_range_param)
    end

    def days_in_range
      (end_date - start_date).to_i + 1
    end

    def prior_period
      self.class.new(start_date: (start_date - days_in_range.days).to_s, end_date: (start_date - 1.day).to_s)
    end

    def to_range
      start_date.beginning_of_day..end_date.end_of_day
    end

    private

    def parse(param)
      PARSERS
        .fetch(param.class) { ->(_) { [ DEFAULT_DAYS.days.ago.to_date, Date.current ] } }
        .call(param)
    end
  end
end
