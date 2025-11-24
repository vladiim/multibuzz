class AddPropertyIndexesToEvents < ActiveRecord::Migration[8.0]
  def change
    # GIN indexes for fast JSONB property queries
    add_index :events, "(properties -> '#{PropertyKeys::HOST}')",
      using: :gin,
      name: "index_events_on_host"

    add_index :events, "(properties -> '#{PropertyKeys::PATH}')",
      using: :gin,
      name: "index_events_on_path"

    # Referrer host for channel attribution queries
    add_index :events, "(properties -> '#{PropertyKeys::REFERRER_HOST}')",
      using: :gin,
      name: "index_events_on_referrer_host"
  end
end
