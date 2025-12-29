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

ActiveRecord::Schema[8.0].define(version: 2025_12_29_223010) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "timescaledb"

  create_table "account_memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "account_id", null: false
    t.integer "role", default: 1, null: false
    t.integer "status", default: 1, null: false
    t.datetime "invited_at"
    t.datetime "accepted_at"
    t.string "invited_by_email"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "invitation_token_digest"
    t.bigint "invited_by_id"
    t.datetime "last_accessed_at"
    t.index ["account_id", "role"], name: "index_account_memberships_on_account_id_and_role"
    t.index ["account_id", "status"], name: "index_account_memberships_on_account_id_and_status"
    t.index ["account_id"], name: "index_account_memberships_on_account_id"
    t.index ["deleted_at"], name: "index_account_memberships_on_deleted_at"
    t.index ["invitation_token_digest"], name: "index_account_memberships_on_invitation_token_digest", unique: true
    t.index ["invited_by_id"], name: "index_account_memberships_on_invited_by_id"
    t.index ["user_id", "account_id"], name: "index_account_memberships_unique_active", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_account_memberships_on_user_id"
  end

  create_table "accounts", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "settings"
    t.datetime "suspended_at"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "plan_id"
    t.integer "billing_status", default: 0, null: false
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.string "billing_email"
    t.datetime "free_until"
    t.datetime "trial_ends_at"
    t.datetime "subscription_started_at"
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.datetime "payment_failed_at"
    t.datetime "grace_period_ends_at"
    t.integer "reruns_used_this_period", default: 0, null: false
    t.integer "onboarding_progress", default: 1, null: false
    t.integer "onboarding_persona"
    t.string "selected_sdk"
    t.datetime "onboarding_started_at"
    t.datetime "onboarding_completed_at"
    t.datetime "activated_at"
    t.datetime "onboarding_skipped_at"
    t.string "shopify_domain"
    t.string "shopify_webhook_secret"
    t.index ["billing_status"], name: "index_accounts_on_billing_status"
    t.index ["free_until"], name: "index_accounts_on_free_until"
    t.index ["payment_failed_at"], name: "index_accounts_on_payment_failed_at"
    t.index ["plan_id"], name: "index_accounts_on_plan_id"
    t.index ["shopify_domain"], name: "index_accounts_on_shopify_domain", unique: true, where: "(shopify_domain IS NOT NULL)"
    t.index ["slug"], name: "index_accounts_on_slug", unique: true
    t.index ["status"], name: "index_accounts_on_status"
    t.index ["stripe_customer_id"], name: "index_accounts_on_stripe_customer_id", unique: true
    t.index ["stripe_subscription_id"], name: "index_accounts_on_stripe_subscription_id", unique: true
    t.index ["trial_ends_at"], name: "index_accounts_on_trial_ends_at"
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

  create_table "attribution_credits", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversion_id", null: false
    t.bigint "attribution_model_id", null: false
    t.bigint "session_id", null: false
    t.string "channel", null: false
    t.decimal "credit", precision: 5, scale: 4, null: false
    t.decimal "revenue_credit", precision: 10, scale: 2
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_campaign"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_test", default: false, null: false
    t.integer "model_version"
    t.index ["account_id", "attribution_model_id", "channel"], name: "index_credits_on_account_model_channel"
    t.index ["account_id", "channel"], name: "index_attribution_credits_on_account_id_and_channel"
    t.index ["account_id"], name: "index_attribution_credits_on_account_id"
    t.index ["attribution_model_id", "channel"], name: "index_attribution_credits_on_attribution_model_id_and_channel"
    t.index ["attribution_model_id", "model_version"], name: "index_credits_staleness"
    t.index ["attribution_model_id"], name: "index_attribution_credits_on_attribution_model_id"
    t.index ["conversion_id", "attribution_model_id"], name: "idx_on_conversion_id_attribution_model_id_08931b86a1"
    t.index ["conversion_id"], name: "index_attribution_credits_on_conversion_id"
    t.index ["is_test"], name: "index_attribution_credits_on_is_test"
  end

  create_table "attribution_models", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.integer "model_type", default: 0, null: false
    t.integer "algorithm"
    t.text "dsl_code"
    t.jsonb "compiled_rules", default: {}
    t.boolean "is_active", default: true, null: false
    t.boolean "is_default", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "lookback_days", default: 30, null: false
    t.integer "version", default: 1, null: false
    t.datetime "version_updated_at"
    t.index ["account_id", "is_active"], name: "index_attribution_models_on_account_id_and_is_active"
    t.index ["account_id", "is_default"], name: "index_attribution_models_on_account_id_and_is_default"
    t.index ["account_id", "name"], name: "index_attribution_models_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_attribution_models_on_account_id"
  end

  create_table "billing_events", force: :cascade do |t|
    t.bigint "account_id"
    t.string "stripe_event_id", null: false
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_billing_events_on_account_id"
    t.index ["event_type"], name: "index_billing_events_on_event_type"
    t.index ["processed_at"], name: "index_billing_events_on_processed_at"
    t.index ["stripe_event_id"], name: "index_billing_events_on_stripe_event_id", unique: true
  end

  create_table "conversion_property_keys", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "property_key", null: false
    t.integer "occurrences", default: 0, null: false
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "occurrences"], name: "index_conversion_property_keys_on_account_id_and_occurrences"
    t.index ["account_id", "property_key"], name: "index_conversion_property_keys_on_account_id_and_property_key", unique: true
    t.index ["account_id"], name: "index_conversion_property_keys_on_account_id"
  end

  create_table "conversions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "visitor_id", null: false
    t.bigint "session_id"
    t.bigint "event_id"
    t.string "conversion_type", null: false
    t.decimal "revenue", precision: 10, scale: 2
    t.datetime "converted_at", null: false
    t.bigint "journey_session_ids", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "properties", default: {}, null: false
    t.boolean "is_test", default: false, null: false
    t.string "funnel"
    t.string "currency", default: "USD"
    t.boolean "is_acquisition", default: false, null: false
    t.bigint "identity_id"
    t.index ["account_id", "converted_at"], name: "index_conversions_on_account_id_and_converted_at"
    t.index ["account_id", "funnel"], name: "index_conversions_on_account_funnel"
    t.index ["account_id", "identity_id", "is_acquisition"], name: "index_conversions_on_acquisition_lookup"
    t.index ["account_id"], name: "index_conversions_on_account_id"
    t.index ["conversion_type"], name: "index_conversions_on_conversion_type"
    t.index ["converted_at"], name: "index_conversions_on_converted_at"
    t.index ["identity_id"], name: "index_conversions_on_identity_id"
    t.index ["is_test"], name: "index_conversions_on_is_test"
    t.index ["visitor_id", "converted_at"], name: "index_conversions_on_visitor_id_and_converted_at"
    t.index ["visitor_id"], name: "index_conversions_on_visitor_id"
  end

  create_table "events", primary_key: ["id", "occurred_at"], force: :cascade do |t|
    t.bigserial "id", null: false
    t.bigint "account_id", null: false
    t.bigint "visitor_id", null: false
    t.bigint "session_id", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.jsonb "properties", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_test", default: false, null: false
    t.boolean "locked", default: false, null: false
    t.string "funnel"
    t.index "((properties -> 'host'::text))", name: "index_events_on_host", using: :gin
    t.index "((properties -> 'path'::text))", name: "index_events_on_path", using: :gin
    t.index "((properties -> 'referrer_host'::text))", name: "index_events_on_referrer_host", using: :gin
    t.index "((properties -> 'utm_campaign'::text))", name: "index_events_on_utm_campaign", using: :gin
    t.index "((properties -> 'utm_medium'::text))", name: "index_events_on_utm_medium", using: :gin
    t.index "((properties -> 'utm_source'::text))", name: "index_events_on_utm_source", using: :gin
    t.index "((properties ->> 'funnel'::text))", name: "index_events_on_funnel"
    t.index "((properties ->> 'funnel_step'::text))", name: "index_events_on_funnel_step"
    t.index ["account_id", "event_type"], name: "index_events_on_account_id_and_event_type"
    t.index ["account_id", "funnel"], name: "index_events_on_account_funnel"
    t.index ["account_id", "occurred_at"], name: "index_events_on_account_id_and_occurred_at"
    t.index ["account_id"], name: "index_events_on_account_id"
    t.index ["is_test"], name: "index_events_on_is_test"
    t.index ["locked"], name: "index_events_on_locked"
    t.index ["occurred_at"], name: "events_occurred_at_idx", order: :desc
    t.index ["properties"], name: "index_events_on_properties", using: :gin
    t.index ["session_id"], name: "index_events_on_session_id"
    t.index ["visitor_id"], name: "index_events_on_visitor_id"
  end

  create_table "form_submissions", force: :cascade do |t|
    t.string "type", null: false
    t.string "email", null: false
    t.jsonb "data", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.string "ip_address"
    t.text "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_form_submissions_on_created_at"
    t.index ["email"], name: "index_form_submissions_on_email"
    t.index ["status"], name: "index_form_submissions_on_status"
    t.index ["type"], name: "index_form_submissions_on_type"
  end

  create_table "identities", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "external_id", null: false
    t.jsonb "traits", default: {}
    t.datetime "first_identified_at", null: false
    t.datetime "last_identified_at", null: false
    t.boolean "is_test", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "external_id"], name: "index_identities_on_account_id_and_external_id", unique: true
    t.index ["account_id"], name: "index_identities_on_account_id"
    t.index ["external_id"], name: "index_identities_on_external_id"
    t.index ["is_test"], name: "index_identities_on_is_test"
    t.index ["traits"], name: "index_identities_on_traits", using: :gin
  end

  create_table "plans", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "monthly_price_cents", default: 0, null: false
    t.integer "events_included", null: false
    t.integer "overage_price_cents"
    t.string "stripe_product_id"
    t.string "stripe_price_id"
    t.string "stripe_meter_id"
    t.boolean "is_active", default: true, null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_plans_on_is_active"
    t.index ["slug"], name: "index_plans_on_slug", unique: true
    t.index ["sort_order"], name: "index_plans_on_sort_order"
  end

  create_table "referrer_sources", force: :cascade do |t|
    t.string "domain", null: false
    t.string "source_name", null: false
    t.string "medium", null: false
    t.string "keyword_param"
    t.boolean "is_spam", default: false, null: false
    t.string "data_origin", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["data_origin"], name: "index_referrer_sources_on_data_origin"
    t.index ["domain"], name: "index_referrer_sources_on_domain", unique: true
    t.index ["is_spam"], name: "index_referrer_sources_on_is_spam"
    t.index ["medium"], name: "index_referrer_sources_on_medium"
  end

  create_table "rerun_jobs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "attribution_model_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "total_conversions", null: false
    t.integer "processed_conversions", default: 0, null: false
    t.integer "from_version", null: false
    t.integer "to_version", null: false
    t.integer "overage_blocks", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_rerun_jobs_on_account_id_and_status"
    t.index ["account_id"], name: "index_rerun_jobs_on_account_id"
    t.index ["attribution_model_id", "status"], name: "index_rerun_jobs_on_attribution_model_id_and_status"
    t.index ["attribution_model_id"], name: "index_rerun_jobs_on_attribution_model_id"
  end

  create_table "sessions", primary_key: ["id", "started_at"], force: :cascade do |t|
    t.bigserial "id", null: false
    t.bigint "account_id", null: false
    t.bigint "visitor_id", null: false
    t.string "session_id", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.integer "page_view_count", default: 0, null: false
    t.jsonb "initial_utm", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "initial_referrer"
    t.string "channel"
    t.boolean "is_test", default: false, null: false
    t.jsonb "click_ids", default: {}, null: false
    t.datetime "last_activity_at"
    t.string "device_fingerprint"
    t.index ["account_id", "session_id", "started_at"], name: "index_sessions_on_account_id_and_session_id", unique: true
    t.index ["account_id"], name: "index_sessions_on_account_id"
    t.index ["channel"], name: "index_sessions_on_channel"
    t.index ["click_ids"], name: "index_sessions_on_click_ids", using: :gin
    t.index ["ended_at"], name: "index_sessions_on_ended_at"
    t.index ["id", "started_at"], name: "index_sessions_on_id_unique", unique: true
    t.index ["initial_utm"], name: "index_sessions_on_initial_utm", using: :gin
    t.index ["is_test"], name: "index_sessions_on_is_test"
    t.index ["session_id"], name: "index_sessions_on_session_id"
    t.index ["started_at"], name: "index_sessions_on_started_at"
    t.index ["visitor_id", "device_fingerprint", "last_activity_at"], name: "index_sessions_for_resolution"
    t.index ["visitor_id"], name: "index_sessions_on_visitor_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_admin", default: false, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "visitors", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "visitor_id", null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.jsonb "traits", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_test", default: false, null: false
    t.bigint "identity_id"
    t.index ["account_id", "visitor_id"], name: "index_visitors_on_account_id_and_visitor_id", unique: true
    t.index ["account_id"], name: "index_visitors_on_account_id"
    t.index ["identity_id"], name: "index_visitors_on_identity_id"
    t.index ["is_test"], name: "index_visitors_on_is_test"
    t.index ["last_seen_at"], name: "index_visitors_on_last_seen_at"
    t.index ["traits"], name: "index_visitors_on_traits", using: :gin
    t.index ["visitor_id"], name: "index_visitors_on_visitor_id"
  end

  add_foreign_key "account_memberships", "accounts"
  add_foreign_key "account_memberships", "users"
  add_foreign_key "accounts", "plans"
  add_foreign_key "api_keys", "accounts"
  add_foreign_key "attribution_credits", "accounts"
  add_foreign_key "attribution_credits", "attribution_models"
  add_foreign_key "attribution_credits", "conversions"
  add_foreign_key "attribution_models", "accounts"
  add_foreign_key "billing_events", "accounts"
  add_foreign_key "conversion_property_keys", "accounts"
  add_foreign_key "conversions", "accounts"
  add_foreign_key "conversions", "identities"
  add_foreign_key "conversions", "visitors"
  add_foreign_key "events", "accounts"
  add_foreign_key "events", "visitors"
  add_foreign_key "identities", "accounts"
  add_foreign_key "rerun_jobs", "accounts"
  add_foreign_key "rerun_jobs", "attribution_models"
  add_foreign_key "sessions", "accounts"
  add_foreign_key "sessions", "visitors"
  add_foreign_key "visitors", "accounts"
  add_foreign_key "visitors", "identities"

  # NOTE: TimescaleDB hypertables and continuous aggregates are excluded from schema.rb
  # They are created via migrations which skip in test environment.
  # Production uses db:migrate which runs the TimescaleDB migrations.
  # See: create_hypertable for events and sessions
  # See: create_continuous_aggregate for channel_attribution_daily, source_attribution_daily
end
