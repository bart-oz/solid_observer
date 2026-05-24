## [0.3.0] - 2026-05-25

> Note: there is no separate `0.2.0` gem release — work originally scoped for v0.2.0 (stability + refactoring, SO-040 through SO-049) was folded into this release.

Headline: **Web UI Dashboard** + stability hardening from pre-release review.

### Added
- Web UI dashboard at `/solid_observer` — queue stats, jobs browser, events log, storage info, responsive layout, optional HTTP Basic Auth
- Web UI config: `ui_enabled`, `ui_username`, `ui_password`, `ui_base_controller`, `ui_refresh_interval`
- Dashboard "Live" toggle: when enabled, only the Right-Now card region (`so_right_now` Turbo Frame) reloads on the configured cadence (`SolidObserver.config.ui_refresh_interval`). Scoped cards stay frozen until the range selector changes. Toggle state lives in the `?live=on` URL param so it survives range navigations.
- Dashboard now supports a Time-Range selector (`15m`, `30m`, `1h`, `7h`, `1d`, `7d`, `14d`, default `1h`) that scopes the new "Last <range>" card region (Performed / Failed / Enqueue rate). The "Right Now" region (Ready / Scheduled / Claimed / Failed-awaiting-retry / Workers) is unaffected by the range and reflects current SolidQueue state.
- Retry / discard actions with confirmation dialogs and CSRF protection
- `QueueEventBuffer#metrics` and `#shutdown` (graceful drain on app exit)
- Configuration: `max_buffer_size` (default 10_000), `buffer_overflow_strategy` (`:drop_old` / `:drop_new`), `filter_cache_ttl`
- `Services::DatabaseSize` for cross-adapter table-size measurement; composite indexes and `distinct_job_classes` / `distinct_queue_names` scopes
- Dashboard now shows three throughput counters (Performed last hour, Failed last 24h, Enqueue rate last 5 min) sourced from the events table, alongside existing point-in-time counters. Throughput counters are persistence-mode only.
- Stat counter subtitles ("queued" / "future runs" / "in progress" / "awaiting retry" / "active processes") clarify SolidQueue lifecycle terminology.
- Conceptual hint banner on the dashboard explains the difference between Jobs tab (in-flight + failed) and Events tab (historical record).
- Jobs tab now has an empty state with a hint pointing to Events tab for completed-job history.
- Dashboard polled chart strip and unified card grid: a JSON-fed polling client refreshes six stat cards (Ready, Scheduled, Claimed, Workers, Failed, Enqueue Rate) and three sparklines (Performed/min, Ready depth, Failed/min) every `SolidObserver.config.ui_refresh_interval` seconds (default `30`, `0` disables polling). In realtime mode only the Ready sparkline renders and the Enqueue Rate card is omitted. Toggle in the dashboard top bar enables/disables polling; state lives in `?live=on` URL param. Hand-rolled inline-SVG sparklines, no JS framework, no external chart library.

### Fixed
- **Duration was displayed off by 1000x.** `RecordEvent` stored `ActiveSupport::Notifications::Event#duration` (milliseconds) directly; `format_duration` interpreted it as seconds. Fixed by converting ms → seconds at write time. No data migration needed (fixed before v0.3.0 release); run `bin/rails solid_observer:storage:purge` to clear pre-fix local data.
- **Dashboard chart strip renders populated polylines on first paint** instead of empty placeholders. Server-side `spark_points` helper mirrors the JS `Sparkline.render` projection formula so the first HTML response ships with real data; the first JS poll appends one additional segment with no visible "empty → full" transition.
- **Live toggle cadence label stays in sync with toggle state.** The `.so-toggle__cadence` span now carries `aria-live="polite"` and is updated in the same synchronous tick as the `--on` class toggle. Server-side ERB hardcodes `"5s"` / `"off"` matching the JS literals.
- Jobs details page no longer crashes for `SolidQueue::FailedExecution`; Queue and Priority now fall back to underlying `SolidQueue::Job` values and show `N/A` when unavailable.
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

### Removed
- Removed the legacy implicit dashboard auto-refresh (`<meta http-equiv="refresh">` plus inline fetch/DOM-swap script for `.so-content`). Replaced by explicit, opt-in Live Mode targeting only the Right-Now frame.
- Removed the legacy `GET /solid_observer/right_now` HTML endpoint and its action template (it was the SO-060-era polling target that returned a partial-only HTML response wrapped in a turbo-frame). Replaced by `GET /solid_observer/poll_data` which returns JSON for the polling client. The `live_poll.js` script-delivery route is unchanged.
- **Removed `SolidObserver.config.ui_refresh_interval`** (was unreliable; cadence is now hardcoded at 5s). Upgrade note: remove the line from your initializer or boot will raise `NoMethodError`.

### Changed
- Web UI controllers refactored to thin actions + query/param/presenter objects; Rails built-in number helpers replace custom ones
- Specs: `allow_any_instance_of` → `instance_double`; sleep-based timer specs use deterministic synchronisation; dead private-method `describe` blocks removed
- `.reek.yml` suppressions trimmed; hot-path services/buffer/engine methods refactored to pass `TooManyStatements` without new suppressions
- `SolidObserver.config.ui_refresh_interval` now controls Live Mode polling cadence instead of implicit full-page dashboard refresh. Default value is unchanged.
- Dashboard default range is `15m` (was `1h`); aligns with poll default.
- Live polling pauses while the tab is hidden and resumes on return (one immediate tick on visibility return so the user doesn't wait up to 5s for fresh data).
- Jobs tab default filter changed from `status=ready` to `status=all_active` (ready + scheduled + claimed + failed).
- Duration values on the Events index and detail pages now use per-event-type semantic context via `<abbr title="...">` tooltips so operators can distinguish enqueue call latency (`job_enqueued`) from perform-time duration (`job_completed` / `job_failed` / `job_discarded`).
- Refreshed the engine UI to a minimalist visual language: light surfaces, near-black text, restrained semantic colour accents reserved for badges/state, hairline separators, consistent rounding. Sidebar moves from dark slate to a light surface. No external CSS dependencies, no JS, no dark mode (single light theme).
- Dashboard: replaced the multi-line "Recent Failures" panel with a single-line **Stability** indicator (pill badge + summary + "View failures" link). Three states based on rolling failure counts: **Stable** (no failures in last 24h), **Degraded** (failures in last 24h but none in last hour), **Critical** (any failure in the last hour). Click-through targets the Events page filtered to `job_failed`.
- Dashboard: removed the "Jobs tab / Events tab" orientation banner. The distinction is discoverable via navigation; the dashboard is reserved for signal.
- Dashboard layout consolidated: dropped the previous two-frame split (Right-Now + Scoped) and the redundant Performed-in-range / Failed-in-range cards (those metrics now live in the polled sparkline strip).
- Live toggle restyled as a pill switch with cadence visible in-line ("Live · 2s" / "Live · off") and a pulsing dot when active.

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
