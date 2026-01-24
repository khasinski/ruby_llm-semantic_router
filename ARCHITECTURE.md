# Architecture

This document describes the architecture and design decisions of RubyLLM Semantic Router.

## Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         Router                              │
│  - Manages agents and conversation state                    │
│  - Delegates routing to strategy                            │
│  - Handles agent switching and chat                         │
│  - Provides ask, ask_batch, match, debug_routing APIs       │
└─────────────────────────────────────────────────────────────┘
           │                    │                    │
           │                    │                    │
           ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ EmbeddingCache  │  │     Logger      │  │  Retry Logic    │
│ (optional TTL)  │  │   (optional)    │  │ (exp. backoff)  │
└─────────────────┘  └─────────────────┘  └─────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Strategies::Semantic                     │
│  - Generates embeddings via RubyLLM                         │
│  - Finds nearest neighbors (kNN)                            │
│  - Returns RoutingDecision                                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Example Storage                         │
│  - In-memory arrays                                         │
│  - ActiveRecord with neighbor gem                           │
│  - Custom vector databases via find_examples                │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### Router (`lib/rubyllm/semantic_router/router.rb`)

The main entry point that orchestrates routing and agent management.

**Responsibilities:**
- Accept and normalize agent configurations
- Store and manage routing examples
- Delegate routing decisions to the strategy
- Maintain conversation state and agent switching
- Provide the `ask`, `ask_batch`, `match`, and `debug_routing` APIs
- Manage embedding cache (if configured)
- Handle retry logic for transient failures
- Emit debug logs (if logger configured)

**Key Design Decisions:**
- Accepts RubyLLM chat objects directly for ergonomic API
- Extracts configuration from chat objects (instructions, tools, model)
- Maintains single chat instance, switching agent config on route changes
- Preserves full conversation history across agent switches

### Strategy (`lib/rubyllm/semantic_router/strategies/`)

Pluggable routing strategies following the Strategy pattern.

**Base Class:** `Strategies::Base`
- Defines the `#route` interface
- Provides shared `apply_fallback` logic

**Semantic Strategy:** `Strategies::Semantic`
- Generates embeddings using RubyLLM.embed
- Performs kNN search against examples
- Supports multiple storage backends via duck typing
- Returns `RoutingDecision` with agent, confidence, and reason

### RoutingDecision (`lib/rubyllm/semantic_router/routing_decision.rb`)

Value object representing a routing decision.

**Attributes:**
- `agent` - Target agent name (symbol)
- `confidence` - Match confidence (0.0-1.0)
- `matched_example` - The example text that matched
- `reason` - Why this decision was made (`:semantic_match`, `:fallback`, etc.)
- `inject_instruction` - Optional instruction for clarification flow

### Configuration (`lib/rubyllm/semantic_router/configuration.rb`)

Global configuration with validation. All setters validate input and raise `ConfigurationError` for invalid values.

**Routing Options:**
- `default_embedding_model` - Model for generating embeddings
- `default_similarity_threshold` - Minimum confidence for routing (0.0-1.0)
- `default_k_neighbors` - Number of neighbors for kNN
- `default_fallback` - Behavior when no match found
- `default_max_words` - Message truncation limit

**Reliability Options:**
- `logger` - Logger instance for debug output (default: nil)
- `cache_ttl` - Embedding cache TTL in seconds (default: nil = no caching)
- `max_retries` - Maximum retry attempts for embedding failures (default: 3)
- `retry_base_delay` - Base delay for exponential backoff in seconds (default: 0.5)

### Utils (`lib/rubyllm/semantic_router/utils.rb`)

Shared utility functions.

- `cosine_distance(a, b)` - Calculate cosine distance between vectors
- `cosine_similarity(a, b)` - Calculate cosine similarity
- `truncate_to_max_words(text, max_words)` - Truncate text by word count

### EmbeddingCache (`lib/rubyllm/semantic_router/embedding_cache.rb`)

Thread-safe in-memory cache for embeddings with TTL support.

**Purpose:** Reduce API calls and latency when the same text is embedded multiple times (e.g., adding the same example after clearing, or routing identical messages).

**Features:**
- TTL-based expiration
- Thread-safe with Mutex
- Simple get/set/fetch interface
- Automatic cleanup of expired entries

```ruby
# Internal structure
CacheEntry = Struct.new(:embedding, :expires_at)

# Usage (internal to Router)
@embedding_cache.fetch(text) { generate_embedding_api_call(text) }
```

**Note:** The cache is per-router instance. Each router maintains its own cache.

### Errors (`lib/rubyllm/semantic_router/errors.rb`)

Custom exception hierarchy for clear error handling.

```
Error (base)
├── AgentNotFoundError
├── NoDefaultAgentError
├── NoAgentsError
├── NoRoutingExamplesError
├── EmbeddingError
├── InvalidFallbackError
├── InvalidAgentError
└── ConfigurationError
```

## Storage Backends

The router supports multiple storage backends through duck typing:

### In-Memory

Default storage using simple arrays of `InMemoryExample` structs.

```ruby
# Internal structure
InMemoryExample = Struct.new(:agent_name, :example_text, :embedding)
```

### ActiveRecord with neighbor gem

Expects model with `has_neighbors :embedding` and `agent_name`, `example_text` columns.

```ruby
# Detection
examples.respond_to?(:nearest_neighbors)  # Use neighbor gem's kNN
```

### Custom Vector Database

Accepts a `find_examples` callable for custom search:

```ruby
find_examples: ->(embedding, limit:) {
  # Return array of hashes or objects with:
  # - agent_name (required)
  # - example_text (optional)
  # - distance OR score (optional, defaults to 0)
}
```

## Routing Flow

1. **Message received** via `router.ask(message)`
2. **Log** routing attempt (if logger configured)
3. **Check cache** for existing embedding (if cache enabled)
4. **Generate embedding** for the message using configured model
   - On failure: retry with exponential backoff (up to `max_retries`)
   - Cache result (if cache enabled)
5. **Find nearest neighbors** from examples (k = `k_neighbors`)
6. **Calculate confidence** from cosine distance of best match
7. **Apply threshold** - if below `similarity_threshold`, use fallback
8. **Log** routing decision (if logger configured)
9. **Return decision** with target agent and metadata
10. **Switch agent** if target differs from current
11. **Send message** to current agent's chat and return response

## Batch Routing Flow

For `router.ask_batch(messages)`:

1. **Generate embeddings** for all messages in single API call
2. **Route each message** using its pre-computed embedding
3. **Return array** of `RoutingDecision` objects
4. **Note:** Does not send messages or switch agents - only returns decisions

## Reliability Features

### Logging

When a logger is configured, the router emits debug information:

```
[SemanticRouter] Router initialized with agents: product, support
[SemanticRouter] Routing message: Show me laptops...
[SemanticRouter] Cache hit for embedding
[SemanticRouter] Routed to :product (confidence: 0.892, reason: semantic_match)
[SemanticRouter] Switching from :support to :product
```

Log levels used:
- `debug` - Detailed operation info (routing attempts, cache hits, agent switches)
- `info` - Routing decisions
- `warn` - Retry attempts
- `error` - Final failures after retries exhausted

### Retry with Exponential Backoff

Embedding API calls are retried on failure:

```
Attempt 1: fail → wait 0.5s
Attempt 2: fail → wait 1.0s
Attempt 3: fail → wait 2.0s
Attempt 4: fail → raise EmbeddingError
```

Formula: `delay = retry_base_delay * (2 ** attempt_number)`

### Embedding Cache

Reduces API calls by caching embeddings:

```ruby
# First call - generates embedding, stores in cache
router.add_example("Show products", agent: :product)

# Later - same text uses cached embedding
router.clear_examples!
router.add_example("Show products", agent: :product)  # Cache hit
```

Cache is keyed by the truncated text (after `max_words` applied).

## Design Principles

### 1. Duck Typing for Flexibility

The router uses duck typing to support multiple storage backends without requiring specific interfaces:

```ruby
# ActiveRecord detection
if examples.respond_to?(:nearest_neighbors)
  # Use neighbor gem
elsif examples.respond_to?(:where)
  # Use ActiveRecord scoping
else
  # Use array operations
end
```

### 2. Sensible Defaults

All configuration has reasonable defaults that work out of the box:
- Embedding model: `text-embedding-3-small` (fast, cheap)
- Threshold: `0.7` (balanced precision/recall)
- Fallback: `:default_agent` (predictable behavior)

### 3. Validation at Boundaries

Input validation occurs at configuration and router initialization, failing fast with clear error messages rather than producing undefined behavior during routing.

### 4. Strategy Pattern for Routing

Using the strategy pattern allows for future alternative routing implementations (e.g., keyword-based, LLM-based) without changing the Router class.

### 5. Value Objects for Decisions

`RoutingDecision` is immutable with clear semantics, making it easy to inspect, log, and test routing behavior.

## Extension Points

### Custom Strategies

Create new routing strategies by extending `Strategies::Base`:

```ruby
class MyStrategy < RubyLLM::SemanticRouter::Strategies::Base
  def route(message, agents:, examples:, current_agent:, config:, find_examples: nil)
    # Custom routing logic
    RoutingDecision.new(agent: :some_agent, confidence: 0.9, reason: :custom)
  end
end

router = Router.new(agents: {...}, strategy: MyStrategy.new, ...)
```

### Callbacks

Register callbacks for routing events:

```ruby
router.on(:on_route) do |decision|
  Rails.logger.info("Routed to #{decision.agent} with confidence #{decision.confidence}")
end
```

## Performance Considerations

- **Embedding generation** is the main latency source (~50-200ms per call)
- **In-memory kNN** is O(n) - fine for hundreds of examples
- **neighbor gem** uses database indexes for O(log n) performance
- **Batch imports** (`import_examples`) reduce embedding API calls
- **Batch routing** (`ask_batch`) generates all embeddings in one API call
- **Embedding cache** eliminates redundant API calls for repeated text
- **max_words** truncation reduces embedding costs for long messages
