<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/solid_logo_dark.svg">
    <source media="(prefers-color-scheme: light)" srcset=".github/solid_logo_light.svg">
    <img alt="SolidObserver" src=".github/solid_logo_light.svg" width="250">
  </picture>
</p>

<p align="center">
  <strong>Observe your Solid Stack like a pro!</strong>
</p>

<p align="center">
  <a href="https://github.com/bart-oz/solid_observer/releases"><img src="https://img.shields.io/badge/version-0.1.1-blue.svg" alt="Version"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://github.com/bart-oz/solid_observer/actions"><img src="https://img.shields.io/badge/tests-passing-brightgreen.svg" alt="Tests"></a>
  <a href="https://github.com/bart-oz/solid_observer/actions"><img src="https://img.shields.io/badge/coverage-94.62%25-brightgreen.svg" alt="Coverage"></a>
</p>

---

SolidObserver is a production-grade observability solution for Rails 8's Solid Stack. Starting with **Solid Queue** monitoring in v0.1.0, it provides unified visibility into your background job processing with a Web UI dashboard, CLI tools, metrics collection, and distributed tracing support.

## Features (v0.2.0)

- 🖥️ **Web UI Dashboard** — Live queue stats, job browser, event log, and storage info
- 📊 **Real-time Queue Status** — Monitor jobs across all states (ready, scheduled, claimed, failed)
- 🔍 **Job Management CLI** — List, inspect, retry, and discard failed jobs
- 💾 **Storage Monitoring** — Track database size and event counts
- 🔗 **Distributed Tracing** — Correlate jobs with APM tools (Datadog, Sentry, OpenTelemetry)
- ⚡ **High Performance** — Buffered writes, configurable sampling, minimal overhead
- 🛡️ **Production Ready** — Docker/CI/K8s safe boot, automatic cleanup, size limits, retention policies
- 🚀 **Two Operating Modes** — Real-time (no migrations) or persistence (full event history)

## Requirements

- Ruby 3.2+
- Rails 8.0+
- Solid Queue (properly configured for all environments)

> **Note:** Ensure Solid Queue is configured with `connects_to` in all environments, not just production. See [Troubleshooting](#troubleshooting) if you encounter database connection issues.

## Installation

Add to your Gemfile:

```ruby
gem "solid_observer"
```

```bash
bundle install
rails generate solid_observer:install
```

SolidObserver supports two operating modes. Choose the one that fits your needs:

### Real-time Mode (no migrations needed)

Get queue monitoring and job management instantly — no database setup required. SolidObserver queries Solid Queue directly.

```ruby
# config/initializers/solid_observer.rb
SolidObserver.configure do |config|
  config.storage_mode = :realtime
end
```

That's it. You now have access to queue status, job listing, retry, and discard commands.

### Persistence Mode (default)

Store event history, metrics, and storage snapshots in a dedicated SQLite database. This gives you everything in real-time mode plus long-term event tracking, buffered writes, and retention-based cleanup.

```bash
bin/rails solid_observer:install:migrations
bin/rails db:create
bin/rails db:migrate
```

No additional configuration needed — persistence is the default `storage_mode`.

## Quick Start

### Check Queue Status

```bash
bin/rails solid_observer:status
```

Output:
```
📊 SolidObserver Status
==================================================

🚀 Solid Queue

| Metric    | Value |
|-----------|-------|
| Ready     | 42    |
| Scheduled | 15    |
| Claimed   | 3     |
| Failed    | 2     |
| Workers   | 4     |

📋 Queue Depths

| Queue      | Jobs |
|------------|------|
| default    | 38   |
| mailers    | 12   |
| critical   | 10   |
```

### Manage Jobs

```bash
# List jobs (defaults to ready jobs)
bin/rails solid_observer:jobs:list

# List failed jobs
bin/rails "solid_observer:jobs:list[failed]"

# Filter by status, queue, job class, and limit
bin/rails "solid_observer:jobs:list[failed,mailers]"
bin/rails "solid_observer:jobs:list[ready,default,UserNotificationJob,50]"

# Inspect a specific job
bin/rails "solid_observer:jobs:show[JOB_ID]"

# Retry a failed job
bin/rails "solid_observer:jobs:retry[JOB_ID]"

# Discard a failed job
bin/rails "solid_observer:jobs:discard[JOB_ID]"
```

### Check Storage (Persistence Mode)

```bash
bin/rails solid_observer:storage
```

Output:
```
💾 Storage Status

| Component | Size    | Events | Usage | Status |
|-----------|---------|--------|-------|--------|
| Queue     | 12.5 MB | 45,231 | 1.2%  | ✓      |

Configuration:
  Retention: 30 days
  Max size:  1024.0 MB per database
  Warning:   80% threshold
```

## Configuration

After installation, configure SolidObserver in `config/initializers/solid_observer.rb`:

```ruby
SolidObserver.configure do |config|
  # Storage Mode (:persistence or :realtime)
  # :persistence — stores events, metrics, snapshots (requires migrations)
  # :realtime    — live monitoring only, no database needed
  config.storage_mode = :persistence  # default

  # Enable queue monitoring (default: true)
  config.observe_queue = true

  # Data Retention (persistence mode only)
  config.event_retention = 30.days    # Keep events for 30 days
  config.metrics_retention = 90.days  # Keep metrics for 90 days

  # Database Limits (persistence mode only)
  config.max_db_size = 1.gigabyte     # Maximum database size
  config.warning_threshold = 0.8      # Warn at 80% capacity

  # Performance Tuning (persistence mode only)
  config.buffer_size = 1000           # Buffer before flushing to DB
  config.flush_interval = 10.seconds  # Flush interval
  config.sampling_rate = 1.0          # 1.0 = capture all events
end
```

### APM Integration

Connect SolidObserver with your Application Performance Monitoring tool for distributed tracing:

```ruby
SolidObserver.configure do |config|
  # Datadog APM
  config.correlation_id_generator = -> {
    Datadog::Tracing.active_trace&.id
  }

  # Sentry
  config.correlation_id_generator = -> {
    Sentry.get_current_scope&.transaction&.trace_id
  }

  # OpenTelemetry
  config.correlation_id_generator = -> {
    OpenTelemetry::Trace.current_span&.context&.trace_id
  }

  # Custom implementation
  config.correlation_id_generator = -> {
    Thread.current[:request_id] || SecureRandom.uuid
  }
end
```

When configured, all job events will include your correlation ID, allowing you to trace jobs back to the originating request.

## CLI Reference

**Available in both modes (real-time and persistence):**

| Command | Description |
|---------|-------------|
| `solid_observer:status` | Show queue status overview |
| `solid_observer:jobs:list[status,queue,class,limit]` | List jobs with optional filters |
| `solid_observer:jobs:show[ID]` | Show job details |
| `solid_observer:jobs:retry[ID]` | Retry a failed job |
| `solid_observer:jobs:discard[ID]` | Discard a failed job |

**Persistence mode only:**

| Command | Description |
|---------|-------------|
| `solid_observer:storage` | Show storage statistics |
| `solid_observer:buffer:flush` | Force flush event buffer to database |
| `solid_observer:buffer:clear` | Clear buffer without saving |
| `solid_observer:storage:cleanup` | Run retention-based cleanup |
| `solid_observer:storage:purge` | Delete ALL SolidObserver data |

> **Note:** Storage commands manage **SolidObserver's storage** (event logs, metrics, snapshots) — not Solid Queue's jobs. To manage jobs, use `jobs:discard` or `jobs:retry`.

### Jobs List Arguments

Arguments are positional: `[status, queue, job_class, limit]`

| Position | Description | Example |
|----------|-------------|---------|
| 1st | Filter by status | `failed`, `ready`, `scheduled` |
| 2nd | Filter by queue name | `default`, `mailers` |
| 3rd | Filter by job class | `UserNotificationJob` |
| 4th | Max results (default: 20) | `50` |

```bash
# Examples
bin/rails solid_observer:jobs:list                           # All ready jobs
bin/rails "solid_observer:jobs:list[failed]"                 # Failed jobs
bin/rails "solid_observer:jobs:list[ready,mailers]"          # Ready jobs in mailers queue
bin/rails "solid_observer:jobs:list[failed,,,50]"            # 50 failed jobs (skip queue/class)
```

### Buffer & Storage Management (Persistence Mode)

```bash
# Flush in-memory buffer to database
bin/rails solid_observer:buffer:flush

# Clear buffer without saving (loses pending events!)
bin/rails solid_observer:buffer:clear

# Run cleanup based on retention policy (default: 30 days)
bin/rails solid_observer:storage:cleanup

# Delete ALL SolidObserver data (events + snapshots, interactive confirmation)
bin/rails solid_observer:storage:purge
```

> **Important:** `storage:purge` deletes SolidObserver's monitoring data, NOT your Solid Queue jobs. Your queued jobs remain safe.

## Database Setup (Persistence Mode)

> **Tip:** If you're using real-time mode (`storage_mode: :realtime`), you can skip this section entirely — no database setup is needed.

**SolidObserver works with any main application database** — PostgreSQL, MySQL, or SQLite.

For its own monitoring data, SolidObserver uses a **separate SQLite database**. This keeps monitoring isolated from your main app and provides simple file-based storage that requires no additional infrastructure.

```yaml
# config/database.yml
solid_observer_queue:
  <<: *default
  adapter: sqlite3  # Always SQLite for SolidObserver storage
  database: storage/<%= Rails.env %>_solid_observer_queue.sqlite3
```

> **Note:** Your main app's `primary` database can be PostgreSQL, MySQL, or any Rails-supported adapter. Only the `solid_observer_queue` database needs to be SQLite.

## Roadmap

SolidObserver is actively developed. Here's what's coming:

| Version | Focus | Status |
|---------|-------|--------|
| v0.1.0 | Solid Queue monitoring, CLI tools | ✅ Released |
| v0.1.1 | Real-time mode (no migrations needed) | ✅ Current |
| v0.2.0 | Web UI dashboard (vanilla HTML/CSS) | 🔜 Planned |
| v0.3.0 | Solid Cache monitoring | 🔜 Planned |
| v0.4.0 | Solid Cable monitoring | 🔜 Planned |
| v0.5.0 | Cross-component correlation, health scores | 🔜 Planned |
| v0.6.0 | Alerting & notifications | 🔜 Planned |
| v1.0.0 | Production stable release | 🎯 Goal |

See [GitHub Milestones](https://github.com/bart-oz/solid_observer/milestones) for detailed plans.

## Development

```bash
# Clone the repository
git clone https://github.com/bart-oz/solid_observer.git
cd solid_observer

# Install dependencies
bin/setup

# Run tests
bundle exec rspec

# Run linter
bundle exec standardrb

# Run code smell detector
bundle exec reek
```

## Troubleshooting

### Docker, CI, and Offline Boot

SolidObserver is designed to boot without a live database connection. During
`rails assets:precompile`, CI runs without a database service, or Kubernetes init
containers, the engine logs a single info message and skips subscriber activation:

```text
[SolidObserver] Database not reachable at boot. Skipping subscriber activation.
```

No monkey-patching or environment-variable workarounds are needed. Once the application
boots with a live database, the engine activates normally on the next restart.

### "no such table: solid_queue_ready_executions"

This error means Solid Queue isn't configured to use the correct database in your environment.

**Solution:** Ensure `connects_to` is configured for all environments, not just production:

```ruby
# config/environments/development.rb
config.solid_queue.connects_to = { database: { writing: :queue } }

# config/environments/test.rb
config.solid_queue.connects_to = { database: { writing: :queue } }
```

### Multi-database setup

SolidObserver works with Rails multi-database configurations. Here's an example with PostgreSQL as your primary database:

```yaml
development:
  primary:
    adapter: postgresql
    database: myapp_development
    # ... PostgreSQL settings
  queue:
    <<: *default
    adapter: sqlite3
    database: storage/development_queue.sqlite3
    migrations_paths: db/queue_migrate
  solid_observer_queue:
    adapter: sqlite3
    database: storage/development_solid_observer_queue.sqlite3
```

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/bart-oz/solid_observer).

Check out issues labeled:
- [good first issue](https://github.com/bart-oz/solid_observer/labels/good%20first%20issue) — Great for newcomers
- [help wanted](https://github.com/bart-oz/solid_observer/labels/help%20wanted) — We'd love your help

Please follow the [code of conduct](https://github.com/bart-oz/solid_observer/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
