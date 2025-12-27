module Articles
  class Repository
    class << self
      def all
        @articles ||= LoaderService.call
      end

      def published
        all.select(&:published?)
      end

      def find_by_slug(slug)
        all.find { |a| a.slug == slug }
      end

      def find_by_slug!(slug)
        find_by_slug(slug) || raise(ActiveRecord::RecordNotFound, "Article not found: #{slug}")
      end

      def in_section(section)
        published.select { |a| a.section == section }.sort_by(&:section_order)
      end

      def by_section
        published.group_by(&:section)
      end

      def featured(limit: 6)
        published.select { |a| a.priority == Article::PRIORITY_FEATURED }.first(limit)
      end

      def reload!
        @articles = nil
      end
    end
  end
end
