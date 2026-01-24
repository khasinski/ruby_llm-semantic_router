# RubyLLM Semantic Router

Route user messages to specialized LLM agents based on semantic similarity.

## Installation

```ruby
gem 'rubyllm-semantic_router'
```

## Quick Start

```ruby
require 'rubyllm/semantic_router'

# Create agents as RubyLLM chat objects
product = RubyLLM.chat(model: "gpt-4o-mini")
                 .with_instructions("You're a product expert.")

support = RubyLLM.chat(model: "gpt-4o")
                 .with_instructions("You're technical support.")

# Create router
router = RubyLLM::SemanticRouter.new(
  agents: { product: product, support: support },
  default_agent: :product
)

# Add training examples
router.import_examples([
  { text: "Show me laptops", agent: :product },
  { text: "I can't log in", agent: :support },
])

# Chat - routing happens automatically
router.ask("What gaming laptops do you have?")  # → product
router.ask("My order is stuck")                  # → support
```

## How It Works

1. User sends a message
2. Router embeds the message (~2ms, ~$0.00001)
3. Finds similar examples using kNN
4. Routes to the matching agent
5. Agent responds with full conversation history

No LLM call needed for routing - just embeddings.

## Options

```ruby
router = RubyLLM::SemanticRouter.new(
  agents: { ... },
  default_agent: :product,
  similarity_threshold: 0.7,          # Route only if confidence > threshold
  fallback: :default_agent,           # :default_agent | :keep_current | :ask_clarification
  embedding_model: "text-embedding-3-small",
  max_words: 50,                      # Truncate messages to first N words (default: unlimited)
  logger: Rails.logger,               # Enable debug logging (default: nil)
  cache_ttl: 300,                     # Cache embeddings for 5 minutes (default: nil)
  max_retries: 3,                     # Retry failed embedding calls (default: 3)
  retry_base_delay: 0.5               # Base delay for exponential backoff (default: 0.5s)
)
```

## Debugging

```ruby
# Preview without sending
decision = router.match("test message")
decision.agent       # => :product
decision.confidence  # => 0.85

# Detailed routing info
router.debug_routing("test message")
```

## Batch Routing

Route multiple messages efficiently with a single embedding API call:

```ruby
messages = [
  "Show me products",
  "I need help with my account",
  "What's your return policy?"
]

decisions = router.ask_batch(messages)
# => [RoutingDecision, RoutingDecision, RoutingDecision]

decisions.each do |decision|
  puts "#{decision.agent}: confidence #{decision.confidence}"
end
```

## Global Configuration

Set defaults for all routers:

```ruby
RubyLLM::SemanticRouter.configure do |config|
  config.default_embedding_model = "text-embedding-3-small"
  config.default_similarity_threshold = 0.7
  config.default_k_neighbors = 3
  config.default_fallback = :default_agent
  config.default_max_words = nil
  config.logger = Rails.logger
  config.cache_ttl = 300              # 5 minute cache
  config.max_retries = 3
  config.retry_base_delay = 0.5
end
```

## Storage Options

### In-Memory (default)

```ruby
router.add_example("Show products", agent: :product)
router.import_examples([...])
```

### ActiveRecord + neighbor gem

Works with PostgreSQL (pgvector), SQLite (sqlite-vec), MySQL (vector), and [more](https://github.com/ankane/neighbor):

```ruby
class RoutingExample < ApplicationRecord
  has_neighbors :embedding
end

router.with_examples(RoutingExample.all)
router.with_examples(RoutingExample.where(tenant_id: current_tenant.id))
```

### Multi-tenant Scoping

For multi-tenant applications, use the `scope` parameter to isolate routing examples:

```ruby
# Create scoped router
router = RubyLLM::SemanticRouter.new(
  agents: { product: product, support: support },
  default_agent: :product,
  scope: "tenant_123"
)

# With ActiveRecord, add a router_scope column to your model
class RoutingExample < ApplicationRecord
  has_neighbors :embedding
end

# Examples are automatically filtered by scope
router.with_examples(RoutingExample.all)  # Only queries where router_scope = "tenant_123"
```

For in-memory examples, the router filters examples that respond to `router_scope` and match the configured scope.

### Custom Vector Database

```ruby
router = RubyLLM::SemanticRouter.new(
  agents: { ... },
  default_agent: :product,
  find_examples: ->(embedding, limit:) {
    # Pinecone, Qdrant, OpenSearch, etc.
    YourVectorDB.search(embedding, limit: limit).map do |result|
      { agent_name: result.agent, score: result.score }
    end
  }
)
```

Return hashes with `agent_name`, and either `distance` (lower=better) or `score` (higher=better).

## License

MIT
