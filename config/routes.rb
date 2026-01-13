# frozen_string_literal: true

SolidObserver::Engine.routes.draw do
  # Only mount UI routes if enabled in configuration
  if SolidObserver.config.ui_enabled
    # TODO: Add UI routes in SO-013
    # root "dashboard#index"
    # resources :queue_events, only: [:index, :show]
    # resources :metrics, only: [:index]
  end
end
