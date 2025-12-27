module Articles
  class LoaderService
    FILE_PATTERN = "**/*.md.erb".freeze

    def self.call
      new.call
    end

    def call
      article_files.filter_map { |path| load_article(path) }
    end

    private

    def article_files
      Dir.glob(content_path.join(FILE_PATTERN))
    end

    def content_path
      Article::CONTENT_PATH
    end

    def load_article(path)
      content = File.read(path)
      article = Article.from_content(content, file_path: path)

      article if valid?(article)
    rescue StandardError => e
      log_error(path, e)
      nil
    end

    def valid?(article)
      article.title.present? && article.slug.present?
    end

    def log_error(path, error)
      Rails.logger.error("[Articles::LoaderService] Failed to load #{path}: #{error.message}")
    end
  end
end
