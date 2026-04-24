# frozen_string_literal: true

module SolidObserver
  class StoragesController < ApplicationController
    include RequirePersistenceMode

    def show
      @current_storage = SolidObserver::StorageInfo.order(recorded_at: :desc).first
      @storage_history = SolidObserver::StorageInfo.recent(20)
    end
  end
end
