# frozen_string_literal: true

module LandingPages
  class Registry
    Page = Data.define(:slug, :title, :template)

    PAGES = [
      Page.new(slug: "vs-triple-whale", title: "mbuzz vs Triple Whale — Attribution Beyond Shopify", template: "vs_triple_whale"),
      Page.new(slug: "vs-dreamdata", title: "mbuzz vs Dreamdata — B2B Attribution Without the Price Tag", template: "vs_dreamdata"),
      Page.new(slug: "vs-ga4", title: "mbuzz vs GA4 Attribution — See What Google Won't Show You", template: "vs_ga4")
    ].index_by(&:slug).freeze

    def self.find(slug)
      PAGES[slug]
    end

    def self.slugs
      PAGES.keys
    end
  end
end
