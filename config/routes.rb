Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Webhooks (before API routes for clarity)
  namespace :webhooks do
    post "stripe", to: "stripe#create"
    post "shopify", to: "shopify#create"
  end

  # API routes
  namespace :api do
    namespace :v1 do
      resources :events, only: [ :create ]
      resources :sessions, only: [ :create ]
      resources :conversions, only: [ :create ]
      post "identify", to: "identify#create"
      get "validate", to: "validate#show"
      get "health", to: "health#show"

      # Test endpoints (test/dev environments only)
      if Rails.env.test? || Rails.env.development?
        namespace :test do
          resource :setup, only: [ :create, :destroy ]
          resource :verification, only: [ :show, :destroy ]
        end
      end
    end
  end

  # Demo (public, no auth required)
  get "demo", to: "demo#show"
  get "demo/attribution", to: "demo#attribution", as: :demo_attribution

  # Public pages
  get "home", to: "pages#home"
  get "about", to: "pages#about"
  get "privacy", to: "pages#privacy"
  get "terms", to: "pages#terms"
  get "cookies", to: "pages#cookies"
  get "contact", to: "contacts#new"
  post "contact", to: "contacts#create"
  get "contact/thank-you", to: "contacts#show", as: :contact_thank_you

  # Feature waitlist
  post "feature_waitlist", to: "feature_waitlist#create"

  # Signup
  get "signup", to: "signup#new", as: :signup
  post "signup", to: "signup#create"
  get "register", to: redirect("/signup"), as: :new_registration

  # Onboarding (authenticated)
  get "onboarding", to: "onboarding#show", as: :onboarding
  post "onboarding/persona", to: "onboarding#persona", as: :onboarding_persona
  get "onboarding/setup", to: "onboarding#setup", as: :onboarding_setup
  post "onboarding/regenerate_api_key", to: "onboarding#regenerate_api_key", as: :onboarding_regenerate_api_key
  post "onboarding/select_sdk", to: "onboarding#select_sdk", as: :onboarding_select_sdk
  post "onboarding/waitlist_sdk", to: "onboarding#waitlist_sdk", as: :onboarding_waitlist_sdk
  get "onboarding/install", to: "onboarding#install", as: :onboarding_install
  get "onboarding/verify", to: "onboarding#verify", as: :onboarding_verify
  get "onboarding/event_status", to: "onboarding#event_status", as: :onboarding_event_status
  get "onboarding/conversion", to: "onboarding#conversion", as: :onboarding_conversion
  get "onboarding/attribution", to: "onboarding#attribution", as: :onboarding_attribution
  get "onboarding/complete", to: "onboarding#complete", as: :onboarding_complete
  post "onboarding/skip", to: "onboarding#skip", as: :onboarding_skip

  # Documentation routes
  get "docs", to: redirect("/docs/getting-started"), as: :docs_index
  get "docs/:page", to: "docs#show", as: :docs, constraints: { page: /[\w-]+/ }

  # Dashboard routes
  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy"
  get "dashboard", to: "dashboard#show"

  # Team invitations
  get "invitations/:token/accept", to: "invitations#show", as: :accept_invitation
  post "invitations/:token/accept", to: "invitations#create"
  post "invitations/:id/accept_pending", to: "invitations#accept_pending", as: :accept_pending_invitation

  # Account creation for existing users
  resources :accounts, only: [:new, :create]

  # Admin routes
  namespace :admin do
    get "billing", to: "billing#show", as: :billing
    resources :accounts, only: [:show, :update]
    resources :submissions, only: [:index, :show]
  end

  # Account settings
  resource :account, only: [:show, :update], controller: "account" do
    scope module: :accounts do
      resource :billing, only: [:show], controller: "billing" do
        post :checkout
        get :portal
        get :success
        get :cancel
      end
      resource :team, only: [:show], controller: "team" do
        resources :invitations, only: [:create, :destroy], controller: "team/invitations"
        resources :memberships, only: [:update, :destroy], controller: "team/memberships"
        resource :ownership, only: [], controller: "team/ownership" do
          post :transfer
        end
      end
      resources :api_keys, only: [:index, :create, :destroy]
      resources :attribution_models, except: [:show] do
        collection do
          post :validate
        end
        member do
          post :reset
          post :set_default
          post :rerun
          post :test
        end
      end
    end
  end

  namespace :dashboard do
    patch "view_mode", to: "view_mode#update"
    patch "clv_mode", to: "clv_mode#update"

    # Turbo Frame endpoints for dashboard sections
    get "filters", to: "filters#show"
    get "conversions", to: "conversions#show"
    get "funnel", to: "funnel#show"

    # Conversion filter endpoints
    namespace :conversion_filters do
      get :dimensions
      get :values
      post :add_row
      delete :remove_row
    end
  end

  # Redirects from old dashboard routes to new /account routes
  get "dashboard/settings", to: redirect("/account")
  get "dashboard/billing", to: redirect("/account/billing")
  get "dashboard/api_keys", to: redirect("/account/api_keys")

  root "pages#home"
end
