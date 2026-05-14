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
      # Dashboard (read-only aggregated metrics for the cockpit)
      get "dashboard/summary", to: "dashboard#summary"

      # Users & RBAC
      resources :users, only: %i[index show create update destroy] do
        member do
          post   :assign_role
          delete :remove_role
        end
      end
      resources :roles,       only: %i[index show create update destroy]
      resources :permissions, only: %i[index]

      # Catalog
      resources :products, only: %i[index show create update destroy] do
        collection do
          get  :export
          post :import
          post "import/commit", action: :import_commit, as: :import_commit
          post :bulk
        end
        resources :images, only: %i[create destroy], controller: "product_images"
      end
      resources :collections, only: %i[index show create update destroy] do
        member do
          post   "products",             action: :add_product,    as: :add_product
          delete "products/:product_id", action: :remove_product, as: :remove_product
        end
      end
      resources :variants, only: %i[index]

      # Sales / Orders
      resources :orders, only: %i[index show create update] do
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

      # Shipping / Fulfillments (view-only; Shopify sync owns fulfillment data)
      resources :fulfillments, only: %i[index show create] do
        collection do
          get  :export
          post :bulk
        end
        member do
          get :events
          patch :annotation
          post :transition_delivery
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
      resources :stock_transfers, only: %i[index show create]
      post "inventory/shopify_backfill", to: "inventory_sync#shopify_backfill"

      # Showroom (consignment) sales reports
      resources :showroom_sales, only: %i[create]

      # Accounting
      scope "/accounting" do
        get  "accounts",                   to: "accounting#accounts"
        get  "journal_entries",            to: "accounting#journal_entries"
        post "journal_entries",            to: "accounting#create_journal_entry"
        get  "journal_entries/:id",        to: "accounting#journal_entry"
        get  "accounts/:code/ledger",      to: "accounting#account_ledger"
        get  "trial_balance",              to: "accounting#trial_balance"
        get  "pnl",                        to: "accounting#pnl"
        get  "balance_sheet",              to: "accounting#balance_sheet"
        post "post_order/:order_id",       to: "accounting#post_order"
      end

      # Ping (used for RBAC smoke tests)
      get "ping", to: "application#ping"

      # Audit log (admin-only)
      resources :audit_logs, only: %i[index]
    end
  end
end
