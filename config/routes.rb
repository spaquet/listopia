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
  get "profile", to: "users#show", as: :profile
  get "profile/edit", to: "users#edit", as: :edit_user
  patch "profile", to: "users#update"
  get "settings", to: "users#settings", as: :settings_user
  patch "settings/password", to: "users#update_password", as: :update_password_user
  patch "settings/preferences", to: "users#update_preferences", as: :update_preferences_user
  patch "settings/notifications", to: "users#update_notification_settings", as: :update_notification_settings_user  # ADD this line

  # Unified invitation acceptance (handles all types: User, List, ListItem, Team, Organization)
  # MUST come before resources :invitations to match before the :id route
  get "/invitations/accept/:token", to: "invitations#accept", as: "accept_invitation"

  # Organization invitation acceptance (alternative route)
  get "/organizations/invitations/accept/:token", to: "organization_invitations#accept", as: "accept_organization_invitation"

  # Invitations management (list sent/received invitations with management features)
  resources :invitations, only: [ :index, :show, :update ] do
    member do
      patch :decline
      delete :revoke
      patch :resend
    end
  end

  # Main application routes (require authentication)

  # Dashboard routes
  get "dashboard", to: "dashboard#index"
  get "dashboard/focus_list", to: "dashboard#focus_list", as: :dashboard_focus_list
  post "dashboard/execute_action", to: "dashboard#execute_action", as: :dashboard_execute_action


  # Chat functionality
  namespace :chat do
    post "messages", to: "chat#create_message"
    get :ai_context
    get "export", to:  "exports#show"
    get "history", to: "chat#load_history"
    get "dashboard_history", to: "chat#load_dashboard_history"
  end
  # post "/chat/messages", to: "chat/chat#create_message", as: :chat_messages

  # Lists
  resources :lists do
    member do
      patch :toggle_status
      patch :toggle_public_access
      post :duplicate
      get :share
      patch :assign
      patch :inline_update
    end

    # Comments on Lists
    resources :comments, only: [ :create, :destroy ]

    # Analytics routes
    resources :analytics, only: [ :index ]

    # Collaborations
    resources :collaborations, except: [ :new, :edit ] do
      member do
        patch :resend
      end
    end

    # List items
    resources :list_items, path: "items", except: [ :new ] do
      member do
        patch :toggle_completion
        get :share
      end

      # Collaborations on ListItems
      resources :collaborations, except: [ :new, :edit ]

      collection do
        patch :bulk_update
        patch :bulk_complete
        get :context_summary
        patch :reorder
      end

      # Comments on ListItems
      resources :comments, only: [ :create, :destroy ]
    end

    # Collaborations
    resources :collaborations, except: [ :new, :edit ] do
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

  # User management routes, used by admins
  resources :users, only: [ :show, :destroy ] do
    member do
      # Admin actions only (settings routes already defined above for current user)
      post "suspend", to: "users#suspend"
      post "unsuspend", to: "users#unsuspend"
      post "deactivate", to: "users#deactivate"
      post "reactivate", to: "users#reactivate"
      post "grant_admin", to: "users#grant_admin"
      post "revoke_admin", to: "users#revoke_admin"
      patch "update_admin_notes", to: "users#update_admin_notes"
    end
  end

  # Admin user invitation setup
  get "setup_password/:token", to: "registrations#setup_password", as: :setup_password_registration
  post "setup_password/:token", to: "registrations#complete_setup_password", as: :complete_setup_password_registration

  # Organizations - switcher and switching only
  resources :organizations, only: [] do
    collection do
      get :switcher, as: :switcher
      patch :switch
    end

    # Teams - user-facing team management
    resources :teams do
      resources :members, controller: "team_members", only: [ :new, :create ] do
        collection do
          get :search
        end
        member do
          patch :update_role
          delete :remove
          post :resend_invitation
          delete :cancel_invitation
        end
      end
    end
  end

  # Admin routes
  namespace :admin do
    root "dashboard#index"

    resources :users do
      member do
        post :toggle_admin
        post :toggle_status
        post :resend_invitation
      end
      collection do
        post :bulk_action
      end
    end

    resources :organizations do
      member do
        post :suspend
        post :reactivate
        get :audit_logs
      end

      resources :members, controller: "organization_members" do
        member do
          patch :update_role
          delete :remove
        end
      end

      resources :invitations, controller: "organization_invitations" do
        member do
          patch :resend
          delete :revoke
        end
      end

      resources :teams do
        member do
          get :members
        end
        resources :members, controller: "team_members" do
          member do
            patch :update_role
            delete :remove
          end
        end
      end
    end

    resources :lists, only: [ :index, :show, :destroy ]
  end
end
