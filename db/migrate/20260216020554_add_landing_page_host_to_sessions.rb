# frozen_string_literal: true

class AddLandingPageHostToSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sessions, :landing_page_host, :string
    add_index :sessions, [ :account_id, :landing_page_host ], name: "index_sessions_on_account_and_landing_page_host"
  end
end
