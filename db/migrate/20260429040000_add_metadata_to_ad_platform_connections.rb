# frozen_string_literal: true

class AddMetadataToAdPlatformConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :ad_platform_connections, :metadata, :jsonb, null: false, default: {}
  end
end
