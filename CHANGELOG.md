## [0.3.0] - [unreleased]

> Note: there is no separate `0.2.0` gem release — work originally scoped for v0.2.0 (stability + refactoring, SO-040 through SO-049) was folded into this release.

Headline: **Web UI Dashboard** + stability hardening from pre-release review.

### Added
- Web UI dashboard at `/solid_observer` — queue stats, jobs browser, events log, storage info; auto-refresh, responsive layout, optional HTTP Basic Auth
- Web UI config: `ui_enabled`, `ui_username`, `ui_password`, `ui_base_controller`, `ui_refresh_interval`
- Retry / discard actions with confirmation dialogs and CSRF protection
- `QueueEventBuffer#metrics` and `#shutdown` (graceful drain on app exit)
- Configuration: `max_buffer_size` (default 10_000), `buffer_overflow_strategy` (`:drop_old` / `:drop_new`), `filter_cache_ttl`
- `Services::DatabaseSize` for cross-adapter table-size measurement; composite indexes and `distinct_job_classes` / `distinct_queue_names` scopes
- Dashboard now shows three throughput counters (Performed last hour, Failed last 24h, Enqueue rate last 5 min) sourced from the events table, alongside existing point-in-time counters. Throughput counters are persistence-mode only.
- Stat counter subtitles ("queued" / "future runs" / "in progress" / "awaiting retry" / "active processes") clarify SolidQueue lifecycle terminology.
- Conceptual hint banner on the dashboard explains the difference between Jobs tab (in-flight + failed) and Events tab (historical record).
- Jobs tab now has an empty state with a hint pointing to Events tab for completed-job history.

### Fixed
- Web UI now works on API-only Rails hosts. The engine ships its own Cookies / Session::CookieStore (`key: "_solid_observer_session"`) / Flash middleware stack, so requests routed to `/solid_observer/*` get the middleware they need regardless of whether the host app strips them via `config.api_only = true`. Previously, API-only hosts hit `NoMethodError: undefined method 'flash' for an instance of ActionDispatch::Request` rendering the dashboard layout.
- `bin/rails solid_observer:install:migrations` now respects `migrations_paths` from the `solid_observer_queue` connection in `config/database.yml`. When the host configures a dedicated migration folder (e.g. `db/solid_observer_migrate`), the install task copies migrations directly there instead of `db/migrate/`. Previously, operators in multi-database setups had to manually move the files after install to prevent cross-database migration contamination.
- Web UI now degrades gracefully when the `solid_observer_queue` database is missing or unreachable at request time. Previously, requests to `/solid_observer/*` raised `ActiveRecord::NoDatabaseError` / `ConnectionNotEstablished` with a raw 500 stack trace. The engine now renders a 503 "Storage unavailable" page using the dashboard layout, with an actionable hint to run migrations or check `database.yml`. Realtime mode is unaffected. Boot-time resilience (Engine activation skip) was already in place; this closes the equivalent gap at request time.
- Engine boot no longer requires a live DB (Docker/CI/K8s safe); table check uses `BaseEvent.connection_pool` (multi-DB safe); broader rescue covering adapter-specific connection errors
- `QueueEventBuffer` hard-caps at `max_buffer_size` with overflow strategy; uses a single persistent `Concurrent::TimerTask` instead of spawning a thread per flush
- Storage monitoring uses adapter-native size queries (SQLite / PostgreSQL / MySQL / Trilogy) — fixes `0 MB` readings off SQLite
- `EventsController` and `JobsController` filter dropdowns no longer full-table-scan on every request (cached via `filter_cache_ttl`)
- `RecordEvent` correctly handles real `ActiveJob::Base` payload objects (with hash fallback)

### Security
- Job arguments removed from persisted event metadata and the jobs detail view (PII reduction)
- Web UI HTTP Basic Auth now requires **both** `ui_username` and `ui_password` to be configured. Previously, setting only `ui_username` (with `ui_password` missing or `nil`) would still trigger an auth challenge that any blank-password request would pass `secure_compare("", "")`, granting unauthenticated access. The README's "both must be set" guidance now matches the implementation; misconfigured auth now ships unauthenticated rather than allowing a bypass.
- Boot-time `Engine.check_ui_authentication` now warns on partial misconfiguration (exactly one of `ui_username` / `ui_password` set), naming the missing credential. Previously the check exited silently as soon as `ui_username.present?`, hiding the fail-open auth misconfiguration from operators.

### Documentation
- Documented multi-adapter installation (PG host + SQLite observer DB) inline in Database Setup, with explicit `adapter:` override, `gem "sqlite3"` Bundler note, `migrations_paths` migration-isolation guidance, and cross-reference from the install steps.

### Changed
- Web UI controllers refactored to thin actions + query/param/presenter objects; Rails built-in number helpers replace custom ones
- Specs: `allow_any_instance_of` → `instance_double`; sleep-based timer specs use deterministic synchronisation; dead private-method `describe` blocks removed
- `.reek.yml` suppressions trimmed; hot-path services/buffer/engine methods refactored to pass `TooManyStatements` without new suppressions
- Jobs tab default filter changed from `status=ready` to `status=all_active` (ready + scheduled + claimed + failed).

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
