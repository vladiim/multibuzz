# frozen_string_literal: true

class GuidedSetup < ApplicationRecord
  include GuidedSetup::Enums
  include GuidedSetup::Relationships
  include GuidedSetup::Validations
  include GuidedSetup::Scopes
  include GuidedSetup::Milestones
  include GuidedSetup::PaymentJourney
  include GuidedSetup::Recommendations

  has_prefix_id :gst
end
