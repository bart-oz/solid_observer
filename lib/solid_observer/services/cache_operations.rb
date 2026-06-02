# frozen_string_literal: true

module SolidObserver
  module Services
    class CacheOperations
      MESSAGES = {
        clear: {
          confirmation: "Clear all SolidCache entries? This evicts cached application data and may slow requests while the cache rebuilds. This cannot be undone.",
          success: "Cache cleared successfully.",
          failure: "Cache clear failed. SolidCache is unavailable or rejected the operation."
        }.freeze,
        prune: {
          success: "Expired cache entries pruned successfully.",
          failure: "Cache prune failed. SolidCache is unavailable or rejected the operation."
        }.freeze,
        unavailable: "Cache controls are unavailable because SolidCache is not enabled or not detected."
      }.freeze

      class << self
        def available?
          new.available?
        end

        def clear
          new.clear
        end

        def prune
          new.prune
        end

        def message(operation, key = nil)
          return MESSAGES.fetch(:unavailable) if operation == :unavailable

          MESSAGES.fetch(operation).fetch(key)
        end

        def unavailable_message
          message(:unavailable)
        end
      end

      def available?
        SolidObserver.config.solid_cache_enabled? && compatible_store?
      end

      def clear
        messages = self.class
        return {ok: false, message: messages.unavailable_message} unless available?

        perform_operation(
          :clear,
          success_message: messages.message(:clear, :success),
          failure_message: messages.message(:clear, :failure)
        ) do
          cache_store.clear
        end
      end

      def prune
        messages = self.class
        return {ok: false, message: messages.unavailable_message} unless available?

        perform_operation(
          :prune,
          success_message: messages.message(:prune, :success),
          failure_message: messages.message(:prune, :failure)
        ) do
          prune_with_fallback
        end
      end

      private

      def compatible_store?
        defined?(::SolidCache::Store) && cache_store.is_a?(::SolidCache::Store)
      end

      def cache_store
        Rails.cache
      end

      def perform_operation(name, success_message:, failure_message:)
        yield
        {ok: true, message: success_message}
      rescue => error
        log_failure(name, error)
        {ok: false, message: failure_message}
      end

      def prune_with_fallback
        cache_store.cleanup
      rescue NotImplementedError
        prune_with_solid_cache_fallback
      end

      def prune_with_solid_cache_fallback
        cache_store.with_each_connection do
          ::SolidCache::Entry.expire(
            cache_store.expiry_batch_size,
            max_age: cache_store.max_age,
            max_entries: cache_store.max_entries,
            max_size: cache_store.max_size
          )
        end
      rescue NameError
        raise "cleanup unsupported"
      end

      def log_failure(name, error)
        Rails.logger&.warn("[SolidObserver] Cache #{name} failed: #{error.class}")
      end
    end
  end
end
