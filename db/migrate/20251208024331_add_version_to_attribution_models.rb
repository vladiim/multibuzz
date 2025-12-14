# frozen_string_literal: true

class AddVersionToAttributionModels < ActiveRecord::Migration[8.0]
  def change
    add_column :attribution_models, :version, :integer, default: 1, null: false
    add_column :attribution_models, :version_updated_at, :datetime

    add_column :attribution_credits, :model_version, :integer
    add_index :attribution_credits, [:attribution_model_id, :model_version], name: "index_credits_staleness"

    add_column :accounts, :reruns_used_this_period, :integer, default: 0, null: false
  end
end
