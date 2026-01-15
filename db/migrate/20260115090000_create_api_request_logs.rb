# frozen_string_literal: true

class CreateApiRequestLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :api_request_logs do |t|
      t.references :account, null: true, foreign_key: true
      t.string :request_id, null: false
      t.string :endpoint, null: false
      t.string :http_method, null: false
      t.integer :http_status, null: false
      t.integer :error_type, null: false
      t.string :error_code
      t.text :error_message
      t.jsonb :error_details, default: {}
      t.string :sdk_name
      t.string :sdk_version
      t.string :ip_address
      t.string :user_agent
      t.jsonb :request_params, default: {}
      t.integer :response_time_ms
      t.datetime :occurred_at, null: false

      t.timestamps

      t.index :request_id
      t.index [:account_id, :occurred_at]
      t.index [:error_type, :occurred_at]
      t.index [:endpoint, :http_status, :occurred_at]
      t.index [:sdk_name, :sdk_version, :occurred_at]
    end
  end
end
