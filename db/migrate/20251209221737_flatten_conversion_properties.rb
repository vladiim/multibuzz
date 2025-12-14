# frozen_string_literal: true

class FlattenConversionProperties < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Flatten nested "properties" key in conversion properties
    # Before: { "url": "...", "referrer": "...", "properties": { "location": "Sydney" } }
    # After:  { "url": "...", "referrer": "...", "location": "Sydney" }
    #
    # This uses a single SQL UPDATE to merge the nested properties to root level
    # and remove the "properties" key

    execute <<~SQL
      UPDATE conversions
      SET properties = (properties - 'properties') || (properties->'properties')
      WHERE properties ? 'properties'
        AND jsonb_typeof(properties->'properties') = 'object'
    SQL
  end

  def down
    # This migration is not easily reversible as we can't determine
    # which keys were originally nested vs at root level.
    # The data is not lost, just restructured.
    raise ActiveRecord::IrreversibleMigration
  end
end
