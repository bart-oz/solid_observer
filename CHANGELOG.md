## [Unreleased]

## [0.1.0] - 2026-01-13

### Added
- Configuration DSL with 17 configurable attributes
- Module-level `configure`, `config`, and `reset_configuration!` methods
- `correlation_id_generator` option for custom correlation ID generation (integrates with Datadog, Sentry, OpenTelemetry)
- Production-aware defaults (UI disabled in production by default)
- Rails idiomatic time helpers for retention periods (30.days, 10.seconds)
- Comprehensive CI pipeline (tests, linting, security, coverage)
- Multi-version testing with Appraisal (Rails 8.0 and 8.1)
- Code quality tools: StandardRB, Reek, SimpleCov, bundler-audit
- Support for Ruby 3.2, 3.3, 3.4, 4.0
- Support for Rails 8.0, 8.1