# Architecture

This document describes the architecture and design decisions of RubyLLM Semantic Router.

## Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         Router                              │
│  - Manages agents and conversation state                    │
│  - Delegates routing to strategy                            │
│  - Handles agent switching and chat                         │
└─────────────────────────────────────────────────────────────┘
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
- Provide the `ask`, `match`, and `debug_routing` APIs

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

Global configuration with validation.

**Configurable Options:**
- `default_embedding_model` - Model for generating embeddings
- `default_similarity_threshold` - Minimum confidence for routing (0.0-1.0)
- `default_k_neighbors` - Number of neighbors for kNN
- `default_fallback` - Behavior when no match found
- `default_max_words` - Message truncation limit

### Utils (`lib/rubyllm/semantic_router/utils.rb`)

Shared utility functions.

- `cosine_distance(a, b)` - Calculate cosine distance between vectors
- `cosine_similarity(a, b)` - Calculate cosine similarity
- `truncate_to_max_words(text, max_words)` - Truncate text by word count

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
2. **Generate embedding** for the message using configured model
3. **Find nearest neighbors** from examples (k = `k_neighbors`)
4. **Calculate confidence** from cosine distance of best match
5. **Apply threshold** - if below `similarity_threshold`, use fallback
6. **Return decision** with target agent and metadata
7. **Switch agent** if target differs from current
8. **Send message** to current agent's chat and return response

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
- **max_words** truncation reduces embedding costs for long messages
