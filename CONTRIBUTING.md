# Contributing to SolidObserver

Thank you for your interest in contributing to SolidObserver! This guide will help you get started.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/solid_observer.git`
3. Create a branch: `git checkout -b my-feature`
4. Make your changes
5. Run the tests: `bundle exec rspec`
6. Commit your changes: `git commit -am 'Add new feature'`
7. Push to your fork: `git push origin my-feature`
8. Create a Pull Request

## Development Setup

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run linter
bundle exec standardrb

# Check for code smells
bundle exec reek

# Check for security vulnerabilities
bundle exec bundler-audit
```

## Pull Request Guidelines

- Keep changes focused and atomic
- Add tests for new features
- Update documentation as needed
- Follow the existing code style
- Ensure all tests pass
- Keep the PR description clear and concise

## Code Quality

We use several tools to maintain code quality:

- **StandardRB** for code formatting
- **Reek** for code smell detection
- **SimpleCov** for test coverage (minimum 80%)
- **RSpec** for testing

Run quality checks before submitting:

```bash
bundle exec standardrb --fix  # Auto-fix style issues
bundle exec reek             # Check for code smells
bundle exec rspec            # Run full test suite
```

## Testing

- Write tests for all new features
- Maintain test coverage above 80%
- Include unit, integration, and edge case tests
- Use descriptive test names

Example:

```ruby
RSpec.describe SolidObserver::Configuration do
  it "validates sampling rate is between 0 and 1" do
    expect { config.sampling_rate = 1.5 }.to raise_error(ArgumentError)
  end
end
```

## Commit Messages

- Use clear, descriptive commit messages
- Start with a verb in present tense (Add, Fix, Update, Remove)
- Keep the first line under 72 characters
- Add details in the body if needed

Examples:
- ✅ `Add correlation ID support for APM integrations`
- ✅ `Fix buffer flush race condition`
- ❌ `Updated stuff`

## Reporting Issues

When reporting issues, please include:

- Ruby and Rails versions
- SolidObserver version
- Steps to reproduce the issue
- Expected vs actual behavior
- Relevant logs or error messages

## Questions?

- Open an issue for bugs or feature requests
- Check existing issues before creating a new one
- Be respectful and constructive in discussions

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

Thank you for contributing! 🎉
