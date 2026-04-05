# frozen_string_literal: true

module SolidObserver
  class StoragesController < ApplicationController
    before_action :require_persistence_mode

    def show
      @current_storage = SolidObserver::StorageInfo.order(recorded_at: :desc).first
      @storage_history = SolidObserver::StorageInfo.recent(20)
    end
  end
end
