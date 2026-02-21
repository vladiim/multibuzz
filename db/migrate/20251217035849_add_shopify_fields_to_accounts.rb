# frozen_string_literal: true

class AddShopifyFieldsToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :shopify_domain, :string
    add_column :accounts, :shopify_webhook_secret, :string

    add_index :accounts, :shopify_domain, unique: true, where: "shopify_domain IS NOT NULL"
  end
end
