# frozen_string_literal: true

module SolidObserver
  class CacheOperationsController < ApplicationController
    def index
      @cache_controls_available = SolidObserver::Services::CacheOperations.available?
    end

    def prune
      redirect_with_result(SolidObserver::Services::CacheOperations.prune)
    end

    def clear
      redirect_with_result(SolidObserver::Services::CacheOperations.clear)
    end

    private

    def redirect_with_result(result)
      flash_key = result[:ok] ? :notice : :alert
      redirect_to cache_operations_path, flash_key => result[:message]
    end
  end
end
