# frozen_string_literal: true

SolidObserver::Engine.routes.draw do
  # Routes are always drawn; ApplicationController#verify_ui_enabled
  # returns 404 at runtime when ui_enabled is false.
  root "dashboard#index"

  resources :jobs, only: %i[index show] do
    member do
      post :retry
      post :discard
    end
  end

  resource :storage, only: %i[show]
  resources :events, only: %i[index show]
end
