# frozen_string_literal: true

class AddClickIdsToSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sessions, :gclid, :string
    add_column :sessions, :gbraid, :string
    add_column :sessions, :wbraid, :string
    add_column :sessions, :dclid, :string
    add_column :sessions, :msclkid, :string
    add_column :sessions, :fbclid, :string
    add_column :sessions, :ttclid, :string
    add_column :sessions, :li_fat_id, :string
    add_column :sessions, :twclid, :string
    add_column :sessions, :epik, :string
    add_column :sessions, :sclid, :string
  end
end
