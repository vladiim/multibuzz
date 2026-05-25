# frozen_string_literal: true

module GuidedSetup::Enums
  extend ActiveSupport::Concern

  included do
    enum :status, { pending: 0, in_progress: 1, delivered: 2, cancelled: 3 }
    enum :integration_target,
         { meta: "meta", google_ads: "google_ads", sgtm: "sgtm", none: "none" },
         prefix: :integration
  end
end
