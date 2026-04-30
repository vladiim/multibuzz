# frozen_string_literal: true

class CreateAccountFeatureFlags < ActiveRecord::Migration[8.0]
  def change
    create_table :account_feature_flags do |t|
      t.references :account, null: false, foreign_key: true
      t.string :flag_name, null: false

      t.timestamps
    end

    add_index :account_feature_flags, [ :account_id, :flag_name ], unique: true
    add_index :account_feature_flags, :flag_name
  end
end
