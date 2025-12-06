class CreateReferrerSources < ActiveRecord::Migration[8.0]
  def change
    create_table :referrer_sources do |t|
      t.string :domain, null: false
      t.string :source_name, null: false
      t.string :medium, null: false
      t.string :keyword_param
      t.boolean :is_spam, null: false, default: false
      t.string :data_origin, null: false

      t.timestamps
    end

    add_index :referrer_sources, :domain, unique: true
    add_index :referrer_sources, :medium
    add_index :referrer_sources, :is_spam
    add_index :referrer_sources, :data_origin
  end
end
