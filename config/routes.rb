# config/routes.rb
Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by uptime monitors and load balancers.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Root path
  root "home#index"

  # Home pages
  get "about", to: "home#about"
  get "pricing", to: "home#pricing"
  get "contact", to: "home#contact"

  # Authentication routes
  # Registration
  get "sign_up", to: "registrations#new", as: :new_registration
  post "sign_up", to: "registrations#create", as: :registration
  get "verify_email", to: "registrations#email_verification_pending"
  get "verify_email/:token", to: "registrations#verify_email", as: :verify_email_token

  # Sessions - Custom routes for sign in/out
  get "sign_in", to: "sessions#new", as: :new_session
  post "sign_in", to: "sessions#create", as: :session
  delete "sign_out", to: "sessions#destroy", as: :destroy_session

  # Magic link authentication
  post "magic_link", to: "sessions#magic_link"
  get "magic_link_sent", to: "sessions#magic_link_sent"
  get "authenticate/:token", to: "sessions#authenticate_magic_link", as: :authenticate_magic_link

  # User management
  get "profile", to: "users#show", as: :user
  get "profile/edit", to: "users#edit", as: :edit_user
  patch "profile", to: "users#update"
  get "settings", to: "users#settings", as: :settings_user
  patch "settings/password", to: "users#update_password", as: :update_password_user
  patch "settings/preferences", to: "users#update_preferences", as: :update_preferences_user
  patch "settings/notifications", to: "users#update_notification_settings", as: :update_notification_settings_user  # ADD this line


  # Collaboration invitation acceptance
  get "/invitations/accept", to: "collaborations#accept", as: "accept_invitation"

  # Main application routes (require authentication)
  get "dashboard", to: "dashboard#index"

  # Chat functionality
  namespace :chat do
    post "messages", to: "chat#create_message"
    get "history", to: "chat#load_history"
    get "export", to:  "exports#show"
  end
  # post "/chat/messages", to: "chat/chat#create_message", as: :chat_messages

  # Lists
  resources :lists do
    member do
      patch :toggle_status
      patch :toggle_public_access
      post :duplicate
      get :share
    end

    # Analytics routes
    resources :analytics, only: [ :index ]

    # List items
    resources :list_items, path: "items", except: [ :new ] do
      member do
        patch :toggle_completion
      end
      collection do
        patch :bulk_update
        patch :reorder
      end
    end

    # Collaborations
    resources :collaborations, except: [ :show, :new, :edit ] do
      member do
        patch :resend
      end
      collection do
        get :accept, path: "accept/:token", as: :accept
      end
    end
  end

  # Notifications
  resources :notifications, only: [ :index, :show ] do
    member do
      patch :mark_as_read
    end
    collection do
      patch :mark_all_as_read
      patch :mark_all_as_seen
      get :stats
    end
  end

  # Public lists - prettier URLs for sharing (optional, both routes work)
  get "public/:slug", to: "lists#show_by_slug", as: :public_list

  # Admin routes (future)
  namespace :admin do
    root "dashboard#index"
    resources :users
    resources :lists

    # Conversation health monitoring routes
    resources :conversation_health, only: [ :index, :show ] do
      collection do
        post :check_all
      end

      member do
        get :show_chat_details
        post :repair_chat
      end
    end
  end
end
