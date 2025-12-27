## [Unreleased]

## [0.1.0]

### Added - 2025-12-27
- Configuration DSL with 14 configurable attributes
- Module-level `configure`, `config`, and `reset_configuration!` methods
- Production-aware defaults (UI disabled in production by default)
- Rails idiomatic time helpers for retention periods

### Setup project infrastructure - 2025-12-26
- Configure Gemfile with development/test dependencies
- Add comprehensive CI pipeline (tests, linting, security, e2e)
- Setup appraisal for testing Rails 8.0 and 8.1
- Add StandardRB, Reek, SimpleCov, Capybara
- Configure bundler-audit for security scanning
- Update version constants (Ruby 3.2+, Rails 8.0+)