# frozen_string_literal: true

module SolidObserver
  class ApplicationController < ActionController::Base
    if defined?(ActionController::API) &&
        begin
          SolidObserver.config.ui_base_controller.constantize.ancestors.include?(ActionController::API)
        rescue NameError
          false
        end
      include ActionView::Layouts
      include ActionView::Rendering
      include ActionController::RequestForgeryProtection
    end

    protect_from_forgery with: :exception
    before_action :verify_ui_enabled
    before_action :authenticate
    helper_method :persistence_mode?, :realtime_mode?
    layout "solid_observer/application"

    private

    def verify_ui_enabled
      render plain: "Not Found", status: :not_found unless SolidObserver.config.ui_enabled
    end

    def authenticate
      return unless SolidObserver.config.ui_username.present?

      authenticate_or_request_with_http_basic("SolidObserver") do |username, password|
        credentials_valid?(username, password)
      end
    end

    def require_persistence_mode
      return unless realtime_mode?

      redirect_to root_path, alert: "This page is not available in real-time mode."
    end

    def persistence_mode?
      SolidObserver.config.persistence_mode?
    end

    def realtime_mode?
      SolidObserver.config.realtime_mode?
    end

    def credentials_valid?(username, password)
      cfg = SolidObserver.config
      ActiveSupport::SecurityUtils.secure_compare(username.to_s, cfg.ui_username.to_s) &&
        ActiveSupport::SecurityUtils.secure_compare(password.to_s, cfg.ui_password.to_s)
    end
  end
end
