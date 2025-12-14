# frozen_string_literal: true

module Pagination
  extend ActiveSupport::Concern

  included do
    class_attribute :per_page_count, default: 25
  end

  class_methods do
    def per_page(count)
      self.per_page_count = count
    end
  end

  private

  def paginate(scope)
    scope.limit(per_page_count).offset(page_offset)
  end

  def page_offset
    [(current_page - 1) * per_page_count, 0].max
  end

  def current_page
    (params[:page] || 1).to_i
  end
end
