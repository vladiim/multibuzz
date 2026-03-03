# frozen_string_literal: true

module AdPlatforms
  class BaseAdapter
    def initialize(connection)
      @connection = connection
    end

    def fetch_spend(date_range:)
      raise NotImplementedError, "#{self.class}#fetch_spend not implemented"
    end

    def refresh_token!
      raise NotImplementedError, "#{self.class}#refresh_token! not implemented"
    end

    def validate_connection
      raise NotImplementedError, "#{self.class}#validate_connection not implemented"
    end

    private

    attr_reader :connection
  end
end
