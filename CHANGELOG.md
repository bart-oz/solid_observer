## [0.1.1] - 2026-02-10

### Added
- **Real-time mode** (`storage_mode: :realtime`) — run SolidObserver without database migrations
  - Queue status and job management CLI commands work without any SolidObserver database
  - `storage_mode` configuration option (`:persistence` default, `:realtime` for no-DB operation)
  - `persistence_mode?` and `realtime_mode?` configuration predicates
  - Graceful `CLI::Storage` message when in real-time mode
  - Event buffering, metric incrementing, and cleanup automatically disabled in real-time mode

## [0.1.0] - 2026-02-02

### Added

#### Core Infrastructure
- Configuration DSL with 17 configurable attributes
- Rails Engine setup for seamless integration
- Separate database support for observability data
- Module-level `configure`, `config`, and `reset_configuration!` methods
- **QueueEvent validations** with `EVENT_TYPES`
- **Configuration validation**
- **Thread error handling** in `QueueEventBuffer#schedule_flush`

#### Queue Monitoring
- Real-time Solid Queue status monitoring (ready, scheduled, claimed, failed jobs)
- Queue depth tracking per queue name
- Worker count monitoring
- Event collection with buffered writes for performance
- **CleanupJob** inherits from `ActiveJob::Base` for better engine isolation
- **Database maintenance** commands are adapter-aware (SQLite VACUUM, PostgreSQL VACUUM ANALYZE, MySQL OPTIMIZE TABLE)
- **Subscriber** includes idempotency check to prevent duplicate subscriptions
- **RecordEvent** properly populates `job_class` and `queue_name` columns

#### CLI Tools
- `solid_observer:status` — Queue overview with formatted tables
- `solid_observer:jobs:list` — List jobs with filters (status, queue, job_class, limit)
- `solid_observer:jobs:show` — Detailed job inspection
- `solid_observer:jobs:retry` — Retry failed jobs with confirmation
- `solid_observer:jobs:discard` — Discard failed jobs with confirmation
- `solid_observer:storage` — Storage statistics and configuration

#### Database & Migrations
- Queue events migration with indexes for efficient queries
- Metrics migration for aggregated data
- Storage info migration for tracking database health
- Automatic cleanup job for data retention

#### APM Integration
- `correlation_id_generator` option for distributed tracing
- Built-in support for Datadog, Sentry, and OpenTelemetry
- Custom correlation ID generator support

#### Performance
- Buffered event writes (configurable buffer size and flush interval)
- Sampling rate configuration for high-traffic applications
- Insert batching with `insert_all!` for bulk operations

#### Developer Experience
- Rails generator: `rails generate solid_observer:install`
- Production-aware defaults (UI disabled in production)
- Rails idiomatic time helpers (30.days, 10.seconds)
- Comprehensive test suite (250+ tests)

#### Quality & CI
- Multi-version testing (Ruby 3.2-4.0, Rails 8.0-8.1)
- Code quality: StandardRB, Reek, SimpleCov (95%+ coverage)
- Security scanning: bundler-audit, brakeman
- Performance benchmarks
