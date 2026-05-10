# frozen_string_literal: true

SolidObserver::Engine.routes.draw do
  root "dashboard#index"
  get "right_now", to: "dashboard#right_now", as: :right_now
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
