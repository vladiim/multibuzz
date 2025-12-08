# frozen_string_literal: true

module RerunJob::Enums
  extend ActiveSupport::Concern

  included do
    enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }
  end
end
