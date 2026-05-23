# frozen_string_literal: true

SolidObserver.configure do |config|
  config.storage_mode = :persistence
  config.ui_enabled = true
  config.observe_queue = true

  # Uncomment to enable HTTP Basic Auth:
  # config.ui_username = "admin"
  # config.ui_password = "secret"
end
