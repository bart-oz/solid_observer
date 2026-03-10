# frozen_string_literal: true

SolidObserver.configure do |config|
  config.storage_mode = :persistence
  config.ui_enabled = true
  config.observe_queue = true

  # Uncomment to enable HTTP Basic Auth:
  # config.ui_username = "admin"
  # config.ui_password = "secret"

  # Auto-refresh interval in seconds (0 = disabled)
  config.ui_refresh_interval = 0
end
