module Account::Callbacks
  extend ActiveSupport::Concern

  included do
    after_create :create_default_attribution_models
  end

  private

  def create_default_attribution_models
    AttributionAlgorithms::DEFAULTS.each do |algorithm_name|
      attribution_models.create!(name: algorithm_name, is_active: true)
    end
  end
end
