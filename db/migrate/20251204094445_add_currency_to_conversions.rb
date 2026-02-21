# frozen_string_literal: true

class AddCurrencyToConversions < ActiveRecord::Migration[8.0]
  def change
    add_column :conversions, :currency, :string, default: "USD"
  end
end
