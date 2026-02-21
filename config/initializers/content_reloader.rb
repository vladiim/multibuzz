# frozen_string_literal: true

# Reload articles when content files change in development
if Rails.env.development?
  Rails.application.config.to_prepare do
    Articles::Repository.reload!
  end

  # Watch content directory for changes
  content_path = Rails.root.join("app/content/articles")
  Rails.application.config.watchable_dirs[content_path.to_s] = [ :erb, :md ]
end
