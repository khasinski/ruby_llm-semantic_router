# Contributing to RubyLLM Semantic Router

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/rubyllm-semantic_router.git`
3. Install dependencies: `bundle install`
4. Run tests: `bundle exec rspec`

## Development Setup

### Requirements

- Ruby 3.1+
- Bundler 2.0+

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/rubyllm/semantic_router/router_spec.rb

# Run with verbose output
bundle exec rspec --format documentation
```

## Making Changes

### Code Style

- Use frozen string literals (`# frozen_string_literal: true`)
- Follow existing code patterns and naming conventions
- Keep methods focused and under 20 lines when possible
- Add YARD documentation for public methods

### Testing

- Write tests for all new functionality
- Maintain or improve existing test coverage
- Tests should be fast and not require external API calls
- Use the mock RubyLLM classes in `spec/spec_helper.rb`

### Commit Messages

- Use clear, descriptive commit messages
- Start with a verb (Add, Fix, Update, Remove, Refactor)
- Keep the first line under 72 characters
- Reference issues when applicable: `Fix #123`

Examples:
```
Add batch routing support with ask_batch method
Fix configuration validation for edge cases
Update README with multi-tenant scoping docs
```

## Pull Request Process

1. Create a feature branch: `git checkout -b feature/my-feature`
2. Make your changes with tests
3. Run the test suite: `bundle exec rspec`
4. Update CHANGELOG.md with your changes under `[Unreleased]`
5. Push to your fork and create a Pull Request

### PR Checklist

- [ ] Tests pass locally
- [ ] New functionality has tests
- [ ] CHANGELOG.md updated
- [ ] Documentation updated (if applicable)
- [ ] Code follows existing style

## Reporting Issues

When reporting issues, please include:

- Ruby version (`ruby -v`)
- Gem version
- Minimal reproduction steps
- Expected vs actual behavior
- Error messages with backtraces

## Feature Requests

Feature requests are welcome! Please:

- Check existing issues first
- Describe the use case
- Explain why existing functionality doesn't solve it
- Consider if it fits the gem's scope

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for an overview of the codebase structure and design decisions.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
