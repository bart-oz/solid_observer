# frozen_string_literal: true

Rails.application.routes.draw do
  mount SolidObserver::Engine, at: "/solid_observer"
  root to: redirect("/solid_observer")
end
