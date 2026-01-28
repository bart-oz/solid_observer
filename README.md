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
  <a href="https://github.com/bart-oz/solid_observer/releases"><img src="https://img.shields.io/badge/version-0.1.0-blue.svg" alt="Version"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://github.com/bart-oz/solid_observer/actions"><img src="https://img.shields.io/badge/tests-passing-brightgreen.svg" alt="Tests"></a>
  <a href="https://github.com/bart-oz/solid_observer/actions"><img src="https://img.shields.io/badge/coverage-96%25-brightgreen.svg" alt="Coverage"></a>
</p>

---

SolidObserver is a production-grade observability solution for Rails 8's Solid Stack. Starting with **Solid Queue** monitoring in v0.1.0, it provides unified visibility into your background job processing with CLI tools, metrics collection, and distributed tracing support.

## Features (v0.1.0)

- 📊 **Real-time Queue Status** — Monitor jobs across all states (ready, scheduled, claimed, failed)
- 🔍 **Job Management CLI** — List, inspect, retry, and discard failed jobs
- 💾 **Storage Monitoring** — Track database size and event counts
- 🔗 **Distributed Tracing** — Correlate jobs with APM tools (Datadog, Sentry, OpenTelemetry)
- ⚡ **High Performance** — Buffered writes, configurable sampling, minimal overhead
- 🛡️ **Production Ready** — Automatic cleanup, size limits, retention policies

## Requirements

- Ruby 3.2+
- Rails 8.0+
- Solid Queue

## Installation

Add to your Gemfile:

```ruby
gem "solid_observer"
```

Run the installer:

```bash
bundle install
rails generate solid_observer:install
```

Install and run migrations:

```bash
rails solid_observer:install:migrations
rails db:create:solid_observer_queue
rails db:migrate
```

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
bin/rails solid_observer:jobs:list --status=failed

# Filter by queue or job class
bin/rails solid_observer:jobs:list --queue=mailers --limit=50
bin/rails solid_observer:jobs:list --job-class=UserNotificationJob

# Inspect a specific job
bin/rails solid_observer:jobs:show JOB_ID

# Retry a failed job
bin/rails solid_observer:jobs:retry JOB_ID

# Discard a failed job
bin/rails solid_observer:jobs:discard JOB_ID
```

### Check Storage

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
  # Enable queue monitoring (default: true)
  config.observe_queue = true

  # Data Retention
  config.event_retention = 30.days    # Keep events for 30 days
  config.metrics_retention = 90.days  # Keep metrics for 90 days

  # Database Limits
  config.max_db_size = 1.gigabyte     # Maximum database size
  config.warning_threshold = 0.8      # Warn at 80% capacity

  # Performance Tuning
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

| Command | Description |
|---------|-------------|
| `solid_observer:status` | Show queue status overview |
| `solid_observer:jobs:list` | List jobs with optional filters |
| `solid_observer:jobs:show ID` | Show job details |
| `solid_observer:jobs:retry ID` | Retry a failed job |
| `solid_observer:jobs:discard ID` | Discard a failed job |
| `solid_observer:storage` | Show storage statistics |

### Jobs List Options

| Option | Description | Example |
|--------|-------------|---------|
| `--status` | Filter by status | `--status=failed` |
| `--queue` | Filter by queue name | `--queue=mailers` |
| `--job-class` | Filter by job class | `--job-class=UserJob` |
| `--limit` | Max results (default: 20) | `--limit=50` |

## Database Setup

SolidObserver uses a separate SQLite database to avoid impacting your main application:

```yaml
# config/database.yml
solid_observer_queue:
  <<: *default
  database: storage/<%= Rails.env %>_solid_observer_queue.sqlite3
  migrations_paths: db/solid_observer_migrate
```

Migrations are stored in `db/solid_observer_migrate/` and can be run independently.

## Roadmap

SolidObserver is actively developed. Here's what's coming:

| Version | Focus | Status |
|---------|-------|--------|
| v0.1.0 | Solid Queue monitoring, CLI tools | ✅ Current |
| v0.2.0 | Solid Cache monitoring | 🔜 Planned |
| v0.3.0 | Solid Cable monitoring | 🔜 Planned |
| v0.4.0 | Cross-component correlation, health scores | 🔜 Planned |
| v0.5.0 | Alerting & notifications | 🔜 Planned |
| v0.6.0 | Web UI dashboard | 🔜 Planned |
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

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/bart-oz/solid_observer).

Check out issues labeled:
- [good first issue](https://github.com/bart-oz/solid_observer/labels/good%20first%20issue) — Great for newcomers
- [help wanted](https://github.com/bart-oz/solid_observer/labels/help%20wanted) — We'd love your help

Please follow the [code of conduct](https://github.com/bart-oz/solid_observer/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
