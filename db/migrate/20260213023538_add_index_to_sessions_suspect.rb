# frozen_string_literal: true

class AddIndexToSessionsSuspect < ActiveRecord::Migration[8.0]
  def change
    add_index :sessions, :suspect
  end
end
