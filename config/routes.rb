Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # API routes
  namespace :api do
    namespace :v1 do
      resources :events, only: [ :create ]
      resources :conversions, only: [ :create ]
      post "identify", to: "identify#create"
      post "alias", to: "alias#create"
      get "validate", to: "validate#show"
      get "health", to: "health#show"
    end
  end

  # Public pages
  get "home", to: "pages#home"

  # Waitlist
  resources :waitlist, only: [ :new, :create, :show ]

  # Documentation routes
  get "docs/:page", to: "docs#show", as: :docs, constraints: { page: /[\w-]+/ }

  # Dashboard routes
  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy"
  get "dashboard", to: "dashboard#show"

  namespace :dashboard do
    resources :api_keys, only: [ :index, :create, :destroy ]
  end

  root "pages#home"
end
