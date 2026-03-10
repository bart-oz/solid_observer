# frozen_string_literal: true

SolidObserver::Engine.routes.draw do
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
