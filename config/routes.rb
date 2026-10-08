Rails.application.routes.draw do
  devise_for :users, skip: [:registrations]

  # Health check for load balancers / uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  # Public, no-login pages (App Store / Play Store review + users)
  get "legal"           => "public#index"
  get "privacy"         => "public#privacy"
  get "terms"           => "public#terms"
  get "support"         => "public#support"
  get "data-deletion"   => "public#data_deletion", as: :data_deletion
  get "account-deletion" => redirect("/data-deletion")

  # ---- Backend console ----
  root "dashboard#index"

  # Field
  resources :sellers
  resources :routes do
    member { patch :update_frequencies }
  end
  resources :store_registrations, only: [:index, :show] do
    member do
      post :approve
      post :reject
    end
    collection { patch :default_category }
  end
  resources :orders, only: [:index, :show]
  resources :order_batches, only: [:index, :show] do
    member { get :download }
    collection { post :build }
  end

  # Masters
  resources :branches, except: [:show, :destroy]
  resources :warehouses, except: [:show, :destroy]
  resources :brands, except: [:show, :destroy]
  resources :product_categories, except: [:show, :destroy]
  resources :product_tiers, except: [:show, :destroy]
  resources :store_categories, except: [:show, :destroy]
  resources :stores do
    member { get :stock_report; get :stock_history; get :stock_offtake }
  end
  get "replenishment" => "replenishment#index", as: :replenishment_index
  resources :managers, except: [:show, :destroy]
  resources :channels
  resources :products
  resources :product_channels, only: [:index]
  resources :assortment_types, except: [:show]
  resources :assortments do
    member { post :import_items }
  end

  # Field capture (read + CSV export by branch) — shelf audits & competitor prices
  resources :stock_counts, only: [:index] do
    get :download, on: :collection
  end
  resources :competitor_price_checks, only: [:index] do
    get :download, on: :collection
  end
  resources :visits, only: [:index, :show] do
    get :download, on: :collection
  end
  resources :compliance, only: [:index, :show] do
    get :download, on: :collection
  end
  resources :planograms
  resources :promos
  resources :pricing_versions do
    member { patch :publish }
  end
  resources :incentive_schemes, except: [:show]

  # Display/visibility targets: upload the xlsx base (a campaign + from/to), then
  # upload CSV execution evidence inside it (newest supersedes). Store drill-down.
  resources :display_campaigns, only: [:index, :new, :create, :show, :destroy] do
    member do
      post :evidence
      get "stores/:store_id", action: :store, as: :store
    end
  end

  # Bulk CSV upload for masters
  get  "imports/:kind/new"    => "imports#new",    as: :new_import
  get  "imports/:kind/sample" => "imports#sample", as: :sample_import
  post "imports/:kind"        => "imports#create", as: :imports

  # Import / sync job history (Logs screen)
  resources :job_logs, only: [:index, :show] do
    member { get :rejected_csv }
  end
  post "syncs/:kind" => "syncs#create", as: :sync

  # ---- Mobile API (phase 2, JWT) ----
  namespace :api do
    namespace :v1 do
      post   "auth/login"  => "auth#login"
      post   "auth/refresh" => "auth#refresh"
      delete "auth/logout" => "auth#logout"

      get "sync/bootstrap"   => "sync#bootstrap"
      get "sync/products"    => "sync#products"
      get "sync/prices"      => "sync#prices"
      get "sync/stores"      => "sync#stores"
      get "sync/routes"      => "sync#routes"
      get "sync/channels"    => "sync#channels"
      get "sync/planograms"  => "sync#planograms"
      get "sync/promos"      => "sync#promos"
      get "sync/assortments" => "sync#assortments"
      get  "sync/store_performance" => "sync#store_performance"
      post "sync/refresh"           => "sync#refresh"

      resources :orders, only: [:create]
      post "orders/preview" => "orders#preview"
      get "stores/search"                => "stores#search"
      get "stores/:id/order_history"     => "orders#history"
      get "stores/:id/last_stock_counts" => "field_captures#last_stock_counts"
      get "stores/:id/profile"           => "stores#profile"
      get "stores/:id/suggested_order"   => "stores#suggested_order"
      get "stores/:id/prefill"           => "stores#prefill"
      get "stores/:id/cross_sell"        => "stores#cross_sell"
      get "stores/:id/recommended"       => "stores#recommended"
      get "stores/:id/inventory"         => "stores#inventory"

      # Field-manager app views
      get "manager/team"          => "manager#team"
      get "manager/insights"      => "manager#insights"
      get "manager/sellers/:id"   => "manager#seller"
      get "manager/sellers/:id/insights" => "manager#seller_insights"
      get "manager/stores/:id"    => "manager#store"
      get "manager/stores/:id/insights"  => "manager#store_insights"
      get "manager/display"       => "manager#display"
      get "manager/display/stores/:store_id" => "manager#display_store"

      resources :store_registrations, only: [:create, :index]

      post "visits/checkin"             => "visits#checkin"
      post "visits/:client_uuid/checkout" => "visits#checkout"
      get  "visits"                     => "visits#index"

      post "stock_counts"       => "field_captures#stock_counts"
      post "competitor_checks"  => "field_captures#competitor_checks"
      post "visit_photos"       => "field_captures#visit_photos"

      get "me/targets"    => "me#targets"
      get "me/summary"    => "me#summary"
      get "me/call_list"  => "me#call_list"
      get "me/priorities"  => "me#priorities"
      get "me/incentives"  => "me#incentives"
      get "me/leaderboard" => "me#leaderboard"
      get "me/assortment_types" => "me#assortment_types"
      get "me/display_targets" => "me#display_targets"
      get "me/display_targets/summary" => "me#display_summary"
      get "me/display_targets/stores/:store_id" => "me#display_store"
    end
  end

  namespace :admin do
    resources :users, only: [:index, :show, :new, :create, :edit, :update] do
      member do
        patch :add_role
        patch :remove_role
      end
    end
    resources :roles, only: [:index, :new, :create, :edit, :update]

    get   "vcsi_linking"                   => "vcsi_linking#show",              as: :vcsi_linking
    get   "system_settings"                => "system_settings#index",          as: :system_settings
    patch "system_settings/batch_update"   => "system_settings#batch_update",   as: :batch_update_system_settings
    post  "system_settings/test_email"     => "system_settings#test_email",     as: :test_email_system_settings
    post  "system_settings/test_connection" => "system_settings#test_connection", as: :test_connection_system_settings
  end
end
