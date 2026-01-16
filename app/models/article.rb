class Article
  include ActiveModel::Model
  include ActiveModel::Attributes

  CONTENT_PATH = Rails.root.join("app/content/articles")

  SECTIONS = %w[fundamentals models integration funnel-forecasting implementation advanced comparisons mbuzz].freeze
  STATUSES = %w[draft review published].freeze
  PRIORITIES = %w[P0 P1 P2 P3].freeze

  STATUS_DRAFT = "draft".freeze
  STATUS_REVIEW = "review".freeze
  STATUS_PUBLISHED = "published".freeze

  SCHEMA_TYPE_ARTICLE = "Article".freeze
  SCHEMA_TYPE_HOW_TO = "HowTo".freeze
  SCHEMA_TYPE_FAQ_PAGE = "FAQPage".freeze

  DEFAULT_AUTHOR = Author::HOLLY_HENDERSON
  DEFAULT_READING_SPEED = 200 # words per minute
  DEFAULT_SECTION_ORDER = 99
  DEFAULT_STATUS = STATUS_DRAFT
  DEFAULT_PRIORITY = "P2".freeze
  PRIORITY_FEATURED = "P0".freeze

  SCHEMA_CONTEXT = "https://schema.org".freeze
  PUBLISHER_URL = "https://mbuzz.co".freeze
  LOGO_URL = "#{PUBLISHER_URL}/logo.svg".freeze
  PUBLISHER_NAME = "mbuzz".freeze

  attribute :title, :string
  attribute :slug, :string
  attribute :description, :string
  attribute :published_at, :date
  attribute :section, :string
  attribute :section_order, :integer, default: DEFAULT_SECTION_ORDER
  attribute :status, :string, default: DEFAULT_STATUS
  attribute :priority, :string, default: DEFAULT_PRIORITY
  attribute :last_updated, :date
  attribute :category, :string
  attribute :tags, default: -> { [] }
  attribute :related_articles, default: -> { [] }
  attribute :seo, default: -> { {} }
  attribute :aeo, default: -> { {} }
  attribute :schema, default: -> { {} }
  attribute :featured_image, default: -> { {} }
  attribute :og_image, :string
  attribute :has_code_examples, :boolean, default: false
  attribute :has_calculator, :boolean, default: false
  attribute :has_download, :boolean, default: false
  attribute :download, default: -> { {} }
  attribute :content, :string
  attribute :file_path, :string

  class << self
    def from_content(raw_content, file_path:)
      loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [ Date, Time ])
      parsed = FrontMatterParser::Parser.new(:md, loader: loader).call(raw_content)
      frontmatter = parsed.front_matter.deep_symbolize_keys

      new(frontmatter.merge(content: parsed.content, file_path: file_path))
    end
  end

  def published?
    status == STATUS_PUBLISHED && published_at.present? && published_at <= Date.current
  end

  def draft?
    status == STATUS_DRAFT
  end

  def seo_title
    dig_value(seo, :title) || title
  end

  def og_title
    seo_title
  end

  def twitter_title
    seo_title
  end

  def og_image_url
    return nil unless og_image.present?

    ActionController::Base.helpers.asset_path(og_image)
  rescue Propshaft::MissingAssetError
    nil
  end

  def featured_image_url
    path = dig_value(featured_image, :path)
    return nil unless path.present?

    ActionController::Base.helpers.asset_path(path)
  rescue Propshaft::MissingAssetError
    nil
  end

  def author
    dig_value(schema, :author) || DEFAULT_AUTHOR
  end

  def author_profile
    Author.find(author) || Author.default
  end

  def date_modified
    modified = dig_value(schema, :date_modified)
    return modified.to_date if modified.present?
    return File.mtime(file_path).to_date if file_path && File.exist?(file_path)

    published_at
  end

  def word_count
    dig_value(schema, :word_count) || content.to_s.split.size
  end

  def reading_time
    (word_count / DEFAULT_READING_SPEED.to_f).ceil
  end

  def tldr
    dig_value(aeo, :tldr)
  end

  def key_takeaways
    dig_value(aeo, :key_takeaways) || []
  end

  def faq
    dig_value(aeo, :faq) || []
  end

  def target_query
    dig_value(aeo, :target_query)
  end

  def to_param
    slug
  end

  def schema_json_ld
    {
      "@context": SCHEMA_CONTEXT,
      "@type": dig_value(schema, :type) || SCHEMA_TYPE_ARTICLE,
      headline: title,
      description: description,
      author: author_profile&.schema_json_ld || { "@type": "Organization", name: author, url: PUBLISHER_URL },
      publisher: {
        "@type": "Organization",
        name: PUBLISHER_NAME,
        url: PUBLISHER_URL,
        logo: { "@type": "ImageObject", url: LOGO_URL }
      },
      datePublished: published_at&.iso8601,
      dateModified: date_modified&.iso8601,
      image: og_image_url,
      wordCount: word_count,
      keywords: Array(tags).join(", "),
      articleSection: category,
      mainEntityOfPage: { "@type": "WebPage", "@id": article_url }
    }.compact
  end

  def faq_schema_json_ld
    return nil if faq.empty?

    {
      "@context": SCHEMA_CONTEXT,
      "@type": SCHEMA_TYPE_FAQ_PAGE,
      mainEntity: faq.map { |item| faq_item_to_schema(item) }
    }
  end

  private

  def dig_value(hash, key)
    hash.dig(key.to_s) || hash.dig(key.to_sym)
  end

  def article_url
    "#{PUBLISHER_URL}/articles/#{slug}"
  end

  def faq_item_to_schema(item)
    question = dig_value(item, :q) || dig_value(item, :question)
    answer = dig_value(item, :a) || dig_value(item, :answer)

    {
      "@type": "Question",
      name: question,
      acceptedAnswer: { "@type": "Answer", text: answer }
    }
  end
end
