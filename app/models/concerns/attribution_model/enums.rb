# frozen_string_literal: true

module AttributionModel::Enums
  extend ActiveSupport::Concern

  included do
    enum :model_type, { preset: 0, custom: 1 }

    enum :algorithm, {
      first_touch: 0,
      last_touch: 1,
      linear: 2,
      time_decay: 3,
      u_shaped: 4,
      w_shaped: 5,
      participation: 6
    }
  end
end
