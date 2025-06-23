# config/routes.rb

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"

  # Root route
  root "home#index"

  # Static pages
  get "/about", to: "home#about", as: :about
  get "/pricing", to: "home#pricing", as: :pricing
  get "/contact", to: "home#contact", as: :contact

  # Authentication routes (using sessions controller)
  get "/sign_in", to: "sessions#new", as: :new_session
  post "/sign_in", to: "sessions#create", as: :session
  delete "/sign_out", to: "sessions#destroy", as: :sign_out

  # Magic link authentication
  post "/magic_link", to: "sessions#magic_link", as: :magic_link
  get "/magic_link_sent", to: "sessions#magic_link_sent", as: :magic_link_sent
  get "/authenticate/:token", to: "sessions#authenticate_magic_link", as: :authenticate_magic_link

  # Registration routes
  get "/sign_up", to: "registrations#new", as: :new_registration
  post "/sign_up", to: "registrations#create", as: :registration
  get "/verify_email", to: "registrations#email_verification_pending", as: :verify_email
  get "/verify_email/:token", to: "registrations#verify_email", as: :verify_email_token

  # User routes
  resource :user, only: [ :show, :edit, :update ] do
    member do
      get :settings
      patch :update_password
      patch :update_preferences
    end
  end

  # Dashboard
  get "/dashboard", to: "dashboard#index", as: :dashboard

  # Lists routes
  resources :lists do
    member do
      patch :toggle_status
      get :analytics
      get :share
      post :duplicate
    end

    # List items nested under lists
    resources :list_items, path: "items" do
      member do
        patch :toggle_completion
        patch :move
      end

      collection do
        patch :bulk_update
        patch :reorder
      end
    end

    # Collaborations nested under lists
    resources :collaborations, only: [ :index, :create, :update, :destroy ] do
      collection do
        get :accept, path: "accept/:token"
      end
    end
  end

  # Public list access
  get "/public/:slug", to: "public_lists#show", as: :public_list

  # API routes for mobile/external access
  namespace :api do
    namespace :v1 do
      resources :lists, only: [ :index, :show, :create, :update, :destroy ] do
        resources :list_items, path: "items", only: [ :index, :create, :update, :destroy ]
      end
      resources :users, only: [ :show, :update ]
    end
  end

  # Admin routes (for future use)
  namespace :admin do
    resources :users, only: [ :index, :show, :edit, :update, :destroy ]
    resources :lists, only: [ :index, :show, :destroy ]
    root "dashboard#index"
  end

  # Webhook routes (for integrations)
  namespace :webhooks do
    post :stripe, to: "stripe#handle" # For future payment integration
    post :slack, to: "slack#handle"   # For Slack integration
  end

  # Catch-all route for SPA-like behavior (optional)
  # get "*path", to: "application#not_found", constraints: ->(request) { !request.xhr? && request.format.html? }
end
