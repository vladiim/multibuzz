# frozen_string_literal: true

class AddConnectionLimitToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :ad_platform_connection_limit, :integer
  end
end
