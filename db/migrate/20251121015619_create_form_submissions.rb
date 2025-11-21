class CreateFormSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :form_submissions do |t|
      t.string :type, null: false
      t.string :email, null: false
      t.jsonb :data, default: {}, null: false
      t.integer :status, default: 0, null: false
      t.string :ip_address
      t.text :user_agent

      t.timestamps
    end

    add_index :form_submissions, :type
    add_index :form_submissions, :email
    add_index :form_submissions, :status
    add_index :form_submissions, :created_at
  end
end
