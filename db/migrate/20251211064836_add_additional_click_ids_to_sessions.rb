# frozen_string_literal: true

class AddAdditionalClickIdsToSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sessions, :gclsrc, :string
    add_column :sessions, :scclid, :string
    add_column :sessions, :rdt_cid, :string
    add_column :sessions, :qclid, :string
    add_column :sessions, :vmcid, :string
    add_column :sessions, :yclid, :string
    add_column :sessions, :sznclid, :string
  end
end
