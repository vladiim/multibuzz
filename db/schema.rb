# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_11_07_031112) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "settings"
    t.datetime "suspended_at"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_accounts_on_slug", unique: true
    t.index ["status"], name: "index_accounts_on_status"
  end

  create_table "api_keys", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "key_digest", null: false
    t.string "key_prefix", null: false
    t.integer "environment", default: 0, null: false
    t.text "description"
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "environment"], name: "index_api_keys_on_account_id_and_environment"
    t.index ["account_id"], name: "index_api_keys_on_account_id"
    t.index ["environment"], name: "index_api_keys_on_environment"
    t.index ["key_digest"], name: "index_api_keys_on_key_digest", unique: true
    t.index ["key_prefix"], name: "index_api_keys_on_key_prefix"
    t.index ["revoked_at"], name: "index_api_keys_on_revoked_at"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "visitor_id", null: false
    t.string "session_id", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.integer "page_view_count", default: 0, null: false
    t.jsonb "initial_utm", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "session_id"], name: "index_sessions_on_account_id_and_session_id", unique: true
    t.index ["account_id"], name: "index_sessions_on_account_id"
    t.index ["ended_at"], name: "index_sessions_on_ended_at"
    t.index ["initial_utm"], name: "index_sessions_on_initial_utm", using: :gin
    t.index ["session_id"], name: "index_sessions_on_session_id"
    t.index ["started_at"], name: "index_sessions_on_started_at"
    t.index ["visitor_id"], name: "index_sessions_on_visitor_id"
  end

  create_table "visitors", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "visitor_id", null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.jsonb "traits", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "visitor_id"], name: "index_visitors_on_account_id_and_visitor_id", unique: true
    t.index ["account_id"], name: "index_visitors_on_account_id"
    t.index ["last_seen_at"], name: "index_visitors_on_last_seen_at"
    t.index ["traits"], name: "index_visitors_on_traits", using: :gin
    t.index ["visitor_id"], name: "index_visitors_on_visitor_id"
  end

  add_foreign_key "api_keys", "accounts"
  add_foreign_key "sessions", "accounts"
  add_foreign_key "sessions", "visitors"
  add_foreign_key "visitors", "accounts"
end
