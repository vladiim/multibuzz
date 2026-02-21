# frozen_string_literal: true

class AddFunnelToConversions < ActiveRecord::Migration[8.0]
  def change
    add_column :conversions, :funnel, :string
    add_index :conversions, [ :account_id, :funnel ], name: "index_conversions_on_account_funnel"
  end
end
