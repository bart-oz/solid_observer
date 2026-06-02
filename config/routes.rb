# frozen_string_literal: true

SolidObserver::Engine.routes.draw do
  root "dashboard#index"
  get "queue", to: "dashboard#index", defaults: {component: "queue"}, as: :queue_dashboard
  get "cache", to: "dashboard#index", defaults: {component: "cache"}, as: :cache_dashboard
  get "cache/controls", to: "cache_operations#index", as: :cache_operations
  post "cache/controls/prune", to: "cache_operations#prune", as: :prune_cache_operations
  post "cache/controls/clear", to: "cache_operations#clear", as: :clear_cache_operations
  get "poll_data", to: "dashboard#poll_data", as: :poll_data
  get "live_poll.js", to: "dashboard#live_poll", as: :live_poll_script

  resources :jobs, only: %i[index show] do
    member do
      post :retry
      post :discard
    end
  end

  resource :storage, only: %i[show]
  resources :events, only: %i[index show]
end
