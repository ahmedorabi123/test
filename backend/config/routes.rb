Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Shopify webhooks — public endpoint, HMAC-verified, no JWT
  namespace :webhooks do
    post "shopify/:topic", to: "shopify#receive", constraints: { topic: /[a-z_\/]+/ }
  end

  # ── Auth (Devise) ──
  # `devise_for` is mounted OUTSIDE the api/v1 namespace so the Devise scope
  # stays `:user` (giving us `current_user` / `authenticate_user!` / `params[:user]`).
  # URLs are kept under /api/v1/auth/* via `path:`.
  devise_for :users,
    path: "api/v1/auth",
    path_names: { sign_in: "login", sign_out: "logout" },
    controllers: {
      sessions:      "api/v1/auth/sessions",
      registrations: "api/v1/auth/registrations"
    },
    skip: [:passwords, :confirmations, :omniauth_callbacks, :unlocks]

  devise_scope :user do
    get "/api/v1/auth/me", to: "api/v1/auth/sessions#me"
  end

  # API v1
  namespace :api do
    namespace :v1 do
      # Users & RBAC
      resources :users, only: %i[index show create update destroy] do
        member do
          post   :assign_role
          delete :remove_role
        end
      end
      resources :roles,       only: %i[index show]
      resources :permissions, only: %i[index]

      # Catalog
      resources :products, only: %i[index show create update destroy] do
        collection do
          get  :export
          post :import
          post "import/commit", action: :import_commit, as: :import_commit
          post :bulk
        end
      end
      resources :collections, only: %i[index show create update destroy] do
        member do
          post   "products",             action: :add_product,    as: :add_product
          delete "products/:product_id", action: :remove_product, as: :remove_product
        end
      end
      resources :variants, only: %i[index] do
        resources :bom_items, only: %i[index create update destroy]
      end
      resources :production_orders, only: %i[index show create update destroy] do
        member do
          post :run
          post :cancel
          post   "stages",                 action: :add_stage,        as: :add_stage
          patch  "stages/:stage_id",       action: :update_stage,     as: :update_stage
          post   "stages/:stage_id/start", action: :start_stage,      as: :start_stage
          post   "stages/:stage_id/complete", action: :complete_stage, as: :complete_stage
          delete "stages/:stage_id",       action: :destroy_stage,    as: :destroy_stage
        end
      end

      # Sales / Orders
      resources :orders, only: %i[index show create] do
        collection do
          get  :stats
          get  :export
          post :import
          post "import/commit", action: :import_commit, as: :import_commit
          post :bulk
          get  :preview_warehouse
        end
        member do
          post :transition
          get  :stock_allocation
          get  :timeline
        end
      end

      # CRM
      resources :customers, only: %i[index show create update destroy] do
        collection do
          get  :export
          post :import
          post "import/commit", action: :import_commit, as: :import_commit
          post :bulk
        end
      end

      # Shipping / Fulfillments (read-only + manual create for non-Shopify orders)
      resources :fulfillments, only: %i[index show create] do
        collection do
          get  :export
          post :bulk
        end
        member do
          get :events
          patch :annotation
        end
      end

      # Returns / Refunds (read-only from Shopify; create for manual/showroom)
      resources :refunds, only: %i[index show create] do
        collection do
          get  :export
          post :bulk
        end
        member do
          post :transition
          post :cancel
        end
      end

      # Purchases
      resources :suppliers, only: %i[index show create update destroy] do
        collection do
          get  :export
          post :bulk
        end
        member do
          get :purchase_orders
        end
      end
      resources :purchase_orders do
        collection do
          get  :export
          post :bulk
        end
        member do
          post :receive
          post :cancel
        end
      end

      # Inventory
      resources :warehouses,   only: %i[index show create update destroy]
      resources :stock_items,  only: %i[index show create update destroy] do
        collection do
          get  :export
          post :bulk
        end
      end
      resources :stock_transfers, only: %i[create]
      post "inventory/shopify_backfill", to: "inventory_sync#shopify_backfill"

      # Showroom (consignment) sales reports
      resources :showroom_sales, only: %i[create]

      # Accounting
      scope "/accounting" do
        get  "accounts",                   to: "accounting#accounts"
        get  "journal_entries",            to: "accounting#journal_entries"
        post "journal_entries",            to: "accounting#create_journal_entry"
        get  "journal_entries/:id",        to: "accounting#journal_entry"
        get  "trial_balance",              to: "accounting#trial_balance"
        get  "pnl",                        to: "accounting#pnl"
        get  "balance_sheet",              to: "accounting#balance_sheet"
        post "post_order/:order_id",       to: "accounting#post_order"
        post "payroll_entries",            to: "accounting#payroll_entries"
      end

      # Ping (used for RBAC smoke tests)
      get "ping", to: "application#ping"

      # Audit log (admin-only)
      resources :audit_logs, only: %i[index]
    end
  end
end
