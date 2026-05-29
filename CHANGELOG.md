# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-05-29

### Changed
- Verified compatibility with RubyLLM 1.15.0 (tested with real OpenAI API)
- Lowered default `similarity_threshold` from 0.7 to 0.3 to match real-world embedding similarity ranges

### Added
- Integration test suite (`spec/integration/`) for testing against real OpenAI API

## [0.3.0] - 2025-01-24

### Added
- Shared `Utils` module with `cosine_distance`, `cosine_similarity`, and `truncate_to_max_words` methods
- Configuration validation for `similarity_threshold` (must be 0.0-1.0), `k_neighbors` (must be positive integer), `max_words` (must be nil or positive integer), and `fallback` (must be valid symbol)
- `ConfigurationError` exception for invalid configuration values
- Debug logging support with configurable `logger` option
- Embedding cache with TTL support via `cache_ttl` option
- `ask_batch` method for routing multiple messages efficiently
- Retry logic with exponential backoff via `max_retries` and `retry_base_delay` options
- Comprehensive test suite for Utils, Configuration, and edge cases
- CHANGELOG.md, CONTRIBUTING.md, and ARCHITECTURE.md documentation

### Changed
- Extracted duplicate `cosine_distance` and `truncate_to_max_words` implementations into shared Utils module
- Improved error messages for configuration validation

### Breaking Changes
- Configuration now validates values and raises `ConfigurationError` for invalid settings:
  - `similarity_threshold` must be between 0.0 and 1.0
  - `k_neighbors` must be a positive integer
  - `max_words` must be nil or a positive integer
  - `fallback` must be one of `:default_agent`, `:keep_current`, `:ask_clarification`
- Previously, invalid values were silently accepted but could cause unexpected behavior. If your code was using invalid configuration values, you will now receive clear error messages indicating what needs to be fixed.

## [0.2.0] - 2025-01-21

### Added
- `max_words` option to truncate messages before embedding generation
- Global `default_max_words` configuration option
- Message truncation applied consistently to both example import and routing

### Changed
- Updated README to be database-agnostic

## [0.1.3] - 2025-01-20

### Added
- Custom vector search support via `find_examples` callback
- Support for both `distance` (lower=better) and `score` (higher=better) in custom search results
- Documented custom vector database integration (Pinecone, Qdrant, OpenSearch, etc.)

### Fixed
- Dependency versions and file permissions

## [0.1.2] - 2025-01-19

### Changed
- Simplified API to accept `RubyLLM.chat` objects directly as agents
- Agents now extract configuration from chat objects automatically

## [0.1.1] - 2025-01-18

### Added
- ActiveRecord + pgvector example to README
- Installation instructions

### Changed
- Simplified README structure

## [0.1.0] - 2025-01-17

### Added
- Initial implementation of semantic routing for RubyLLM
- Core `Router` class for managing multiple agents
- `Semantic` routing strategy using embeddings and kNN search
- Support for multiple fallback behaviors: `:default_agent`, `:keep_current`, `:ask_clarification`
- In-memory example storage with `add_example` and `import_examples`
- External example sources via `with_examples` (ActiveRecord compatible)
- Scoped examples for multi-tenant applications
- Routing callbacks via `on(:on_route)`
- Debug routing with `match` and `debug_routing` methods
- Global configuration via `RubyLLM::SemanticRouter.configure`
- Comprehensive test suite

[0.4.0]: https://github.com/khasinski/ruby_llm-semantic_router/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/khasinski/ruby_llm-semantic_router/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/khasinski/ruby_llm-semantic_router/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/khasinski/ruby_llm-semantic_router/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/khasinski/ruby_llm-semantic_router/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/khasinski/ruby_llm-semantic_router/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/khasinski/ruby_llm-semantic_router/releases/tag/v0.1.0
