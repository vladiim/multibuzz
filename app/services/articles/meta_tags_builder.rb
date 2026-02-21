# frozen_string_literal: true

module Articles
  class MetaTagsBuilder
    OG_TYPE = "article".freeze
    TWITTER_CARD_TYPE = "summary_large_image".freeze

    def initialize(article)
      @article = article
    end

    def call
      {
        title: article.seo_title,
        description: article.description,
        og: og_tags,
        twitter: twitter_tags,
        article: article_tags
      }
    end

    private

    attr_reader :article

    def og_tags
      {
        title: article.og_title,
        description: article.description,
        image: article.og_image_url,
        type: OG_TYPE
      }
    end

    def twitter_tags
      {
        card: TWITTER_CARD_TYPE,
        title: article.twitter_title,
        description: article.description,
        image: article.og_image_url
      }
    end

    def article_tags
      {
        published_time: article.published_at&.iso8601,
        modified_time: article.date_modified&.iso8601,
        author: article.author,
        section: article.category
      }
    end
  end
end
