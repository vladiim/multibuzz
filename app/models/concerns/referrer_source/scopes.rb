module ReferrerSource::Scopes
  extend ActiveSupport::Concern

  included do
    scope :search, -> { where(medium: ReferrerSources::Mediums::SEARCH) }
    scope :social, -> { where(medium: ReferrerSources::Mediums::SOCIAL) }
    scope :email, -> { where(medium: ReferrerSources::Mediums::EMAIL) }
    scope :video, -> { where(medium: ReferrerSources::Mediums::VIDEO) }
    scope :shopping, -> { where(medium: ReferrerSources::Mediums::SHOPPING) }
    scope :news, -> { where(medium: ReferrerSources::Mediums::NEWS) }

    scope :spam, -> { where(is_spam: true) }
    scope :not_spam, -> { where(is_spam: false) }

    scope :by_origin, ->(origin) { where(data_origin: origin) }
  end

  class_methods do
    def by_domain(domain)
      find_by(domain: domain)
    end
  end
end
