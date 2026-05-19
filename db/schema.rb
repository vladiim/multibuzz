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

ActiveRecord::Schema[8.0].define(version: 2026_05_19_110000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "timescaledb"

  create_table "account_credits", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "applied_plan_id", null: false
    t.integer "amount_cents", null: false
    t.string "source", null: false
    t.integer "status", default: 0, null: false
    t.datetime "granted_at", null: false
    t.string "stripe_balance_transaction_id"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_account_credits_on_account_id_and_status"
    t.index ["account_id"], name: "index_account_credits_on_account_id"
    t.index ["applied_plan_id"], name: "index_account_credits_on_applied_plan_id"
  end

  create_table "account_feature_flags", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "flag_name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "flag_name"], name: "index_account_feature_flags_on_account_id_and_flag_name", unique: true
    t.index ["account_id"], name: "index_account_feature_flags_on_account_id"
    t.index ["flag_name"], name: "index_account_feature_flags_on_flag_name"
  end

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
    t.boolean "live_mode_enabled", default: false, null: false
    t.bigint "lifetime_value_cents", default: 0, null: false
    t.datetime "subscription_cancelled_at"
    t.integer "setup_path"
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

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ad_platform_connections", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "platform", null: false
    t.string "platform_account_id", null: false
    t.string "platform_account_name"
    t.string "currency", limit: 3, null: false
    t.text "access_token"
    t.text "refresh_token"
    t.datetime "token_expires_at"
    t.integer "status", default: 0, null: false
    t.datetime "last_synced_at"
    t.string "last_sync_error"
    t.jsonb "settings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.index ["account_id", "platform", "platform_account_id"], name: "idx_ad_connections_unique", unique: true
    t.index ["account_id"], name: "index_ad_platform_connections_on_account_id"
  end

  create_table "ad_spend_records", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "ad_platform_connection_id", null: false
    t.date "spend_date", null: false
    t.string "channel", null: false
    t.string "platform_campaign_id", null: false
    t.string "campaign_name", null: false
    t.string "campaign_type"
    t.string "network_type"
    t.bigint "spend_micros", default: 0, null: false
    t.string "currency", limit: 3, null: false
    t.bigint "impressions", default: 0, null: false
    t.bigint "clicks", default: 0, null: false
    t.bigint "platform_conversions_micros", default: 0, null: false
    t.bigint "platform_conversion_value_micros", default: 0, null: false
    t.boolean "is_test", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "spend_hour", default: 0, null: false
    t.string "device"
    t.jsonb "metadata", default: {}, null: false
    t.index ["account_id", "ad_platform_connection_id", "spend_date", "spend_hour", "platform_campaign_id", "device", "network_type"], name: "idx_spend_unique", unique: true
    t.index ["account_id", "channel", "spend_date"], name: "idx_spend_date_range"
    t.index ["account_id", "spend_date", "channel"], name: "idx_spend_channel_date"
    t.index ["account_id"], name: "index_ad_spend_records_on_account_id"
    t.index ["ad_platform_connection_id"], name: "index_ad_spend_records_on_ad_platform_connection_id"
    t.index ["is_test"], name: "idx_spend_is_test"
  end

  create_table "ad_spend_sync_runs", force: :cascade do |t|
    t.bigint "ad_platform_connection_id", null: false
    t.date "sync_date", null: false
    t.integer "status", default: 0, null: false
    t.integer "records_synced", default: 0
    t.string "error_message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ad_platform_connection_id", "sync_date"], name: "idx_sync_runs_connection_date"
    t.index ["ad_platform_connection_id"], name: "index_ad_spend_sync_runs_on_ad_platform_connection_id"
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

  create_table "api_request_logs", force: :cascade do |t|
    t.bigint "account_id"
    t.string "request_id", null: false
    t.string "endpoint", null: false
    t.string "http_method", null: false
    t.integer "http_status", null: false
    t.integer "error_type", null: false
    t.string "error_code"
    t.text "error_message"
    t.jsonb "error_details", default: {}
    t.string "sdk_name"
    t.string "sdk_version"
    t.string "ip_address"
    t.string "user_agent"
    t.jsonb "request_params", default: {}
    t.integer "response_time_ms"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "occurred_at"], name: "index_api_request_logs_on_account_id_and_occurred_at"
    t.index ["account_id"], name: "index_api_request_logs_on_account_id"
    t.index ["endpoint", "http_status", "occurred_at"], name: "idx_on_endpoint_http_status_occurred_at_2515f4d5ab"
    t.index ["error_type", "occurred_at"], name: "index_api_request_logs_on_error_type_and_occurred_at"
    t.index ["request_id"], name: "index_api_request_logs_on_request_id"
    t.index ["sdk_name", "sdk_version", "occurred_at"], name: "idx_on_sdk_name_sdk_version_occurred_at_52764bb946"
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

  create_table "consent_logs", force: :cascade do |t|
    t.bigint "account_id"
    t.string "visitor_id"
    t.jsonb "consent_payload", default: {}, null: false
    t.string "ip_hash", null: false
    t.string "country", limit: 2
    t.string "region", limit: 8
    t.string "user_agent"
    t.string "banner_version", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_consent_logs_on_account_id"
    t.index ["created_at"], name: "index_consent_logs_on_created_at"
    t.index ["visitor_id"], name: "index_consent_logs_on_visitor_id"
  end

  create_table "conversion_destinations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "platform", null: false
    t.string "name", null: false
    t.boolean "enabled", default: false, null: false
    t.bigint "attribution_model_id", null: false
    t.string "revenue_mode", default: "full", null: false
    t.decimal "minimum_credit_threshold", precision: 5, scale: 4, default: "0.0", null: false
    t.string "meta_pixel_id"
    t.text "meta_access_token"
    t.string "google_customer_id"
    t.string "google_login_customer_id"
    t.string "google_conversion_action_resource_name"
    t.bigint "ad_platform_connection_id"
    t.jsonb "event_type_mapping", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "enabled"], name: "index_conversion_destinations_on_account_id_and_enabled"
    t.index ["account_id", "platform"], name: "index_conversion_destinations_on_account_id_and_platform"
    t.index ["account_id"], name: "index_conversion_destinations_on_account_id"
    t.index ["ad_platform_connection_id"], name: "index_conversion_destinations_on_ad_platform_connection_id"
    t.index ["attribution_model_id"], name: "index_conversion_destinations_on_attribution_model_id"
  end

  create_table "conversion_dispatches", force: :cascade do |t|
    t.bigint "conversion_id", null: false
    t.bigint "conversion_destination_id", null: false
    t.bigint "account_id", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "payload", default: {}, null: false
    t.jsonb "response", default: {}
    t.text "error"
    t.integer "retries_count", default: 0, null: false
    t.datetime "fired_at"
    t.bigint "attribution_model_id"
    t.decimal "platform_credit_share", precision: 5, scale: 4
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status", "created_at"], name: "idx_conversion_dispatches_admin_lookup"
    t.index ["account_id"], name: "index_conversion_dispatches_on_account_id"
    t.index ["attribution_model_id"], name: "index_conversion_dispatches_on_attribution_model_id"
    t.index ["conversion_destination_id"], name: "index_conversion_dispatches_on_conversion_destination_id"
    t.index ["conversion_id", "conversion_destination_id"], name: "idx_conversion_dispatches_unique_per_destination", unique: true
    t.index ["conversion_id"], name: "index_conversion_dispatches_on_conversion_id"
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
    t.string "idempotency_key"
    t.index ["account_id", "converted_at"], name: "index_conversions_on_account_id_and_converted_at"
    t.index ["account_id", "funnel"], name: "index_conversions_on_account_funnel"
    t.index ["account_id", "idempotency_key"], name: "index_conversions_on_account_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["account_id", "identity_id", "is_acquisition"], name: "index_conversions_on_acquisition_lookup"
    t.index ["account_id"], name: "index_conversions_on_account_id"
    t.index ["conversion_type"], name: "index_conversions_on_conversion_type"
    t.index ["converted_at"], name: "index_conversions_on_converted_at"
    t.index ["identity_id"], name: "index_conversions_on_identity_id"
    t.index ["is_test"], name: "index_conversions_on_is_test"
    t.index ["visitor_id", "converted_at"], name: "index_conversions_on_visitor_id_and_converted_at"
    t.index ["visitor_id"], name: "index_conversions_on_visitor_id"
  end

  create_table "data_integrity_checks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "check_name", null: false
    t.string "status", null: false
    t.float "value", null: false
    t.float "warning_threshold", null: false
    t.float "critical_threshold", null: false
    t.jsonb "details", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "check_name", "created_at"], name: "idx_integrity_checks_account_check_time"
    t.index ["account_id"], name: "index_data_integrity_checks_on_account_id"
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
    t.string "request_id"
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
    t.index ["account_id", "request_id"], name: "index_events_on_account_request_id", where: "(request_id IS NOT NULL)"
    t.index ["account_id"], name: "index_events_on_account_id"
    t.index ["is_test"], name: "index_events_on_is_test"
    t.index ["locked"], name: "index_events_on_locked"
    t.index ["occurred_at"], name: "events_occurred_at_idx", order: :desc
    t.index ["properties"], name: "index_events_on_properties", using: :gin
    t.index ["session_id"], name: "index_events_on_session_id"
    t.index ["visitor_id"], name: "index_events_on_visitor_id"
  end

  create_table "exports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "status", default: 0, null: false
    t.string "export_type", null: false
    t.string "filename"
    t.string "file_path"
    t.jsonb "filter_params", default: {}
    t.datetime "completed_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_exports_on_account_id_and_status"
    t.index ["account_id"], name: "index_exports_on_account_id"
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

  create_table "guided_setups", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "status", default: 0, null: false
    t.string "integration_target", default: "none", null: false
    t.string "specialist_name"
    t.text "scheduling_note"
    t.text "notes"
    t.datetime "accepted_at"
    t.datetime "kickoff_call_at"
    t.datetime "install_completed_at"
    t.datetime "integration_connected_at"
    t.datetime "training_call_at"
    t.datetime "value_check_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_guided_setups_on_account_id", unique: true
    t.index ["status", "updated_at"], name: "index_guided_setups_on_status_and_updated_at"
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
    t.string "email_sha256", limit: 64
    t.string "phone_e164_sha256", limit: 64
    t.string "first_name_sha256", limit: 64
    t.string "last_name_sha256", limit: 64
    t.index ["account_id", "email_sha256"], name: "index_identities_on_account_email_sha256", where: "(email_sha256 IS NOT NULL)"
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
    t.integer "ad_platform_connection_limit"
    t.index ["is_active"], name: "index_plans_on_is_active"
    t.index ["slug"], name: "index_plans_on_slug", unique: true
    t.index ["sort_order"], name: "index_plans_on_sort_order"
  end

  create_table "reattribution_batches", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "trigger", null: false
    t.integer "status", default: 0, null: false
    t.integer "total", default: 0, null: false
    t.integer "processed", default: 0, null: false
    t.integer "failed", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "conversion_ids", default: [], null: false, array: true
    t.index ["account_id", "status"], name: "index_reattribution_batches_on_account_id_and_status"
    t.index ["account_id"], name: "index_reattribution_batches_on_account_id"
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

  create_table "score_assessments", force: :cascade do |t|
    t.bigint "user_id"
    t.float "overall_score", null: false
    t.integer "overall_level", null: false
    t.jsonb "dimension_scores", default: {}, null: false
    t.jsonb "answers", default: [], null: false
    t.jsonb "context", default: {}, null: false
    t.string "source"
    t.jsonb "utm_params", default: {}
    t.string "claim_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id"
    t.index ["account_id"], name: "index_score_assessments_on_account_id"
    t.index ["claim_token"], name: "index_score_assessments_on_claim_token", unique: true, where: "(claim_token IS NOT NULL)"
    t.index ["created_at"], name: "index_score_assessments_on_created_at"
    t.index ["overall_level"], name: "index_score_assessments_on_overall_level"
    t.index ["user_id"], name: "index_score_assessments_on_user_id"
  end

  create_table "score_team_memberships", force: :cascade do |t|
    t.bigint "score_team_id", null: false
    t.bigint "user_id", null: false
    t.bigint "score_assessment_id", null: false
    t.string "role_label"
    t.datetime "joined_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["score_assessment_id"], name: "index_score_team_memberships_on_score_assessment_id"
    t.index ["score_team_id", "user_id"], name: "index_score_team_memberships_on_score_team_id_and_user_id", unique: true
    t.index ["score_team_id"], name: "index_score_team_memberships_on_score_team_id"
    t.index ["user_id"], name: "index_score_team_memberships_on_user_id"
  end

  create_table "score_teams", force: :cascade do |t|
    t.bigint "created_by_id", null: false
    t.string "invite_slug", null: false
    t.integer "member_count", default: 1, null: false
    t.float "alignment_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_score_teams_on_created_by_id"
    t.index ["invite_slug"], name: "index_score_teams_on_invite_slug", unique: true
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
    t.boolean "suspect", default: false, null: false
    t.string "landing_page_host"
    t.text "user_agent"
    t.string "suspect_reason"
    t.string "request_id"
    t.string "fbp"
    t.string "fbc"
    t.string "country", limit: 2
    t.string "postal_code", limit: 16
    t.string "gclid"
    t.index ["account_id", "fbp"], name: "index_sessions_on_account_fbp", where: "(fbp IS NOT NULL)"
    t.index ["account_id", "gclid"], name: "index_sessions_on_account_gclid", where: "(gclid IS NOT NULL)"
    t.index ["account_id", "landing_page_host"], name: "index_sessions_on_account_and_landing_page_host"
    t.index ["account_id", "request_id"], name: "index_sessions_on_account_request_id", where: "(request_id IS NOT NULL)"
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
    t.index ["suspect"], name: "index_sessions_on_suspect"
    t.index ["visitor_id", "device_fingerprint", "last_activity_at"], name: "index_sessions_for_resolution"
    t.index ["visitor_id"], name: "index_sessions_on_visitor_id"
  end

  create_table "solid_errors", force: :cascade do |t|
    t.text "exception_class", null: false
    t.text "message", null: false
    t.text "severity", null: false
    t.text "source"
    t.datetime "resolved_at"
    t.string "fingerprint", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fingerprint"], name: "index_solid_errors_on_fingerprint", unique: true
    t.index ["resolved_at"], name: "index_solid_errors_on_resolved_at"
  end

  create_table "solid_errors_occurrences", force: :cascade do |t|
    t.integer "error_id", null: false
    t.text "backtrace"
    t.json "context"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["error_id"], name: "index_solid_errors_occurrences_on_error_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_admin", default: false, null: false
    t.datetime "last_sign_in_at"
    t.integer "sign_in_count", default: 0, null: false
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

  add_foreign_key "account_credits", "accounts"
  add_foreign_key "account_credits", "plans", column: "applied_plan_id"
  add_foreign_key "account_feature_flags", "accounts"
  add_foreign_key "account_memberships", "accounts"
  add_foreign_key "account_memberships", "users"
  add_foreign_key "accounts", "plans"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ad_platform_connections", "accounts"
  add_foreign_key "ad_spend_records", "accounts"
  add_foreign_key "ad_spend_records", "ad_platform_connections"
  add_foreign_key "ad_spend_sync_runs", "ad_platform_connections"
  add_foreign_key "api_keys", "accounts"
  add_foreign_key "api_request_logs", "accounts"
  add_foreign_key "attribution_credits", "accounts"
  add_foreign_key "attribution_credits", "attribution_models"
  add_foreign_key "attribution_credits", "conversions"
  add_foreign_key "attribution_models", "accounts"
  add_foreign_key "billing_events", "accounts"
  add_foreign_key "consent_logs", "accounts"
  add_foreign_key "conversion_destinations", "accounts"
  add_foreign_key "conversion_destinations", "ad_platform_connections"
  add_foreign_key "conversion_destinations", "attribution_models"
  add_foreign_key "conversion_dispatches", "accounts"
  add_foreign_key "conversion_dispatches", "attribution_models"
  add_foreign_key "conversion_dispatches", "conversion_destinations"
  add_foreign_key "conversion_dispatches", "conversions"
  add_foreign_key "conversion_property_keys", "accounts"
  add_foreign_key "conversions", "accounts"
  add_foreign_key "conversions", "identities"
  add_foreign_key "conversions", "visitors"
  add_foreign_key "data_integrity_checks", "accounts"
  add_foreign_key "events", "accounts"
  add_foreign_key "events", "visitors"
  add_foreign_key "exports", "accounts"
  add_foreign_key "guided_setups", "accounts"
  add_foreign_key "identities", "accounts"
  add_foreign_key "reattribution_batches", "accounts"
  add_foreign_key "rerun_jobs", "accounts"
  add_foreign_key "rerun_jobs", "attribution_models"
  add_foreign_key "score_assessments", "accounts"
  add_foreign_key "score_assessments", "users"
  add_foreign_key "score_team_memberships", "score_assessments"
  add_foreign_key "score_team_memberships", "score_teams"
  add_foreign_key "score_team_memberships", "users"
  add_foreign_key "score_teams", "users", column: "created_by_id"
  add_foreign_key "sessions", "accounts"
  add_foreign_key "sessions", "visitors"
  add_foreign_key "solid_errors_occurrences", "solid_errors", column: "error_id"
  add_foreign_key "visitors", "accounts"
  add_foreign_key "visitors", "identities"
end
