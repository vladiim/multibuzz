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

ActiveRecord::Schema[8.0].define(version: 2025_11_07_011936) do
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

  add_foreign_key "api_keys", "accounts"
end
