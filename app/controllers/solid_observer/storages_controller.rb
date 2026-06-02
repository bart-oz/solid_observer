# frozen_string_literal: true

module SolidObserver
  class StoragesController < ApplicationController
    include RequirePersistenceMode

    def show
      @storage_components = SolidObserver::Services::StorageInfoSnapshot.call
      @storage_history = SolidObserver::StorageInfo.recent(20)
    end
  end
end
