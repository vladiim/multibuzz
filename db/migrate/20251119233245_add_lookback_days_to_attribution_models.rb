class AddLookbackDaysToAttributionModels < ActiveRecord::Migration[8.0]
  def change
    add_column :attribution_models, :lookback_days, :integer, null: false, default: 30
  end
end
