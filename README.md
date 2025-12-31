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
  max_words: 50                       # Truncate messages to first N words (default: unlimited)
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
