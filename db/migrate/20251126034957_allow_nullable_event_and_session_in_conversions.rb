class AllowNullableEventAndSessionInConversions < ActiveRecord::Migration[8.0]
  def change
    # Allow visitor-based conversions without a triggering event
    change_column_null :conversions, :event_id, true

    # Allow visitor-based conversions where visitor has no sessions yet
    change_column_null :conversions, :session_id, true

    # Add properties column for conversion metadata
    add_column :conversions, :properties, :jsonb, default: {}, null: false
  end
end
