module Identity::Scopes
  extend ActiveSupport::Concern

  included do
    default_scope { where(is_test: false) }
    scope :test_data, -> { unscope(where: :is_test).where(is_test: true) }
    scope :recently_identified, -> { order(last_identified_at: :desc) }
  end
end
