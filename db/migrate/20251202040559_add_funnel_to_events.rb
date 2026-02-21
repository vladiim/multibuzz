# frozen_string_literal: true

class AddFunnelToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :funnel, :string
    add_index :events, [ :account_id, :funnel ], name: "index_events_on_account_funnel"
  end
end
