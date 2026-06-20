# frozen_string_literal: true

module SolidObserver
  class CableOperationsController < ApplicationController
    def trim
      redirect_with_result(SolidObserver::Services::CableOperations.trim)
    end

    private

    def redirect_with_result(result)
      flash_key = result[:ok] ? :notice : :alert
      redirect_to cable_dashboard_path, flash_key => result[:message]
    end
  end
end
