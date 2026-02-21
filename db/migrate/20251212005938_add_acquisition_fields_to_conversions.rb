# frozen_string_literal: true

class AddAcquisitionFieldsToConversions < ActiveRecord::Migration[8.0]
  def change
    add_column :conversions, :is_acquisition, :boolean, default: false, null: false
    add_reference :conversions, :identity, foreign_key: true, null: true

    add_index :conversions, [ :account_id, :identity_id, :is_acquisition ],
      name: "index_conversions_on_acquisition_lookup"
  end
end
