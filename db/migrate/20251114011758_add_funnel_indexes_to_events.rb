class AddFunnelIndexesToEvents < ActiveRecord::Migration[8.0]
  def change
    add_index :events, "(properties->>'funnel')", using: :btree, name: "index_events_on_funnel"
    add_index :events, "(properties->>'funnel_step')", using: :btree, name: "index_events_on_funnel_step"
  end
end
