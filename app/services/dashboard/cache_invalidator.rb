module Dashboard
  class CacheInvalidator
    SECTIONS = %w[conversions funnel].freeze

    def initialize(account)
      @account = account
    end

    def call
      SECTIONS.each { |section| invalidate_section(section) }
    end

    private

    attr_reader :account

    def invalidate_section(section)
      Rails.cache.delete_matched("dashboard/#{section}/#{account.prefix_id}/*")
    end
  end
end
