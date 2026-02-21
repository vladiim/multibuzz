# frozen_string_literal: true

class Author
  include ActiveModel::Model
  include ActiveModel::Attributes

  HOLLY_HENDERSON = "holly-henderson".freeze
  DEFAULT_AUTHOR = HOLLY_HENDERSON

  attribute :slug, :string
  attribute :name, :string
  attribute :title, :string
  attribute :bio_short, :string
  attribute :bio_medium, :string
  attribute :bio_long, :string
  attribute :image, :string
  attribute :linkedin_url, :string
  attribute :twitter_url, :string
  attribute :credentials, default: -> { [] }

  AUTHORS = {
    HOLLY_HENDERSON => {
      slug: HOLLY_HENDERSON,
      name: "Holly Henderson",
      title: "Co-Founder",
      image: "authors/holly-henderson.jpeg",
      linkedin_url: "https://www.linkedin.com/in/hollymehakovic/",
      credentials: [ "Harvard Extension School", "Forebrite", "Westpac", "Avon" ],
      bio_short: "Holly Henderson is Co-Founder of mbuzz. With 10+ years in marketing " \
                 "including roles at Westpac, Avon, and Forebrite, she's obsessed with making " \
                 "measurement actually useful.",
      bio_medium: "Holly Henderson is Co-Founder of mbuzz, the attribution platform that " \
                  "validates marketing measurement with incrementality testing. After a decade " \
                  "in brand marketing—including campaigns for Avon, Westpac, and content strategies " \
                  "for IP Australia—she joined Forebrite, where she runs weekly client optimization " \
                  "sessions built on attribution-driven revenue forecasting. Sitting in those " \
                  "meetings—watching forecasts hit or miss, debugging why channels " \
                  "underperformed—showed her exactly where attribution breaks down. " \
                  "mbuzz was built to close that gap.",
      bio_long: "Holly Henderson is Co-Founder of mbuzz, where she leads marketing and content " \
                "strategy. Her path to marketing measurement wasn't typical—she spent a decade " \
                "as a brand marketer, running campaigns for companies like Avon and Westpac, and " \
                "creating content strategies for IP Australia and Switzer.\n\n" \
                "The turning point came when she joined Forebrite as their inaugural marketing " \
                "hire. Forebrite builds bottom-up revenue forecasts using multi-touch attribution, " \
                "then runs weekly reconciliation meetings with clients. Holly's been in hundreds " \
                "of those sessions—watching predictions hit or miss, debugging why the forecast " \
                "was off, learning what attribution can and can't tell you about real business " \
                "outcomes.\n\n" \
                "That hands-on experience is why mbuzz exists: attribution you can validate with " \
                "incrementality testing, not just dashboards that look convincing. Holly writes " \
                "about making measurement practical for marketers who care about results, not " \
                "just reports."
    }.freeze
  }.freeze

  class << self
    def find(slug)
      data = AUTHORS[slug.to_s]
      return nil unless data

      new(data)
    end

    def default
      find(DEFAULT_AUTHOR)
    end

    def holly
      find(HOLLY_HENDERSON)
    end
  end

  def to_param
    slug
  end

  def schema_json_ld
    {
      "@type": "Person",
      name: name,
      url: linkedin_url,
      jobTitle: title,
      worksFor: {
        "@type": "Organization",
        name: "mbuzz",
        url: "https://mbuzz.co"
      }
    }.compact
  end
end
