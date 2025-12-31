# RubyLLM Semantic Router

Route user messages to specialized LLM agents based on semantic similarity. Think of it as a fast, embedding-based classifier that decides which expert should handle each message.

## The Problem

You have multiple specialized chat agents:
- A **product expert** that knows your catalog
- An **account manager** that handles billing and settings
- A **support agent** that troubleshoots issues

How do you decide which one handles "I can't log in" vs "What's your return policy" vs "Show me laptops under $1000"?

**Option A**: One mega-agent with all tools and a complex system prompt. Works, but gets confused with 20+ tools.

**Option B**: Route first, then chat. This gem.

## How It Works

```
User: "What's your cheapest laptop?"
            │
            ▼
   ┌─────────────────┐
   │  Embed message  │  ← ~2ms, $0.00001
   └────────┬────────┘
            │
            ▼
   ┌─────────────────┐
   │  Find similar   │  ← Compare to your examples
   │  examples (kNN) │     "Show me computers" → product
   └────────┬────────┘     "Reset password" → account
            │
            ▼
   ┌─────────────────┐
   │  Route to       │  ← Product agent handles it
   │  Product Agent  │
   └─────────────────┘
```

**Key insight**: The routing decision is just an embedding + kNN lookup. No LLM call needed. Fast and cheap.

## Quick Start

```ruby
require 'rubyllm/semantic_router'

# 1. Define your agents as regular RubyLLM chat objects
product_chat = RubyLLM.chat(model: "gpt-4o-mini")
                      .with_instructions("You're a product expert. Help users find products.")

support_chat = RubyLLM.chat(model: "gpt-4o")
                      .with_instructions("You're technical support. Troubleshoot issues.")
                      .with_tools(DiagnosticTool, TicketCreator)

# 2. Create router with your agents
router = RubyLLM::SemanticRouter.new(
  agents: {
    product: product_chat,
    support: support_chat
  },
  default_agent: :product  # Fallback when uncertain
)

# 3. Train with examples (the more, the better)
router.import_examples([
  { text: "Show me laptops", agent: :product },
  { text: "Compare these two phones", agent: :product },
  { text: "What's on sale?", agent: :product },
  { text: "I can't log in", agent: :support },
  { text: "App keeps crashing", agent: :support },
  { text: "Error message when I checkout", agent: :support },
])

# 4. Chat! Routing happens automatically.
router.ask("What gaming laptops do you have?")  # → product agent
router.ask("My order is stuck")                  # → support agent
```

## When To Use This

**Good fit:**
- High-volume customer service with 3+ clearly separated domains
- Different models per task (cheap for FAQ, expensive for reasoning)
- Compliance requirements that need audit trails per agent
- Tool sets that would confuse a single LLM if combined

**Probably overkill:**
- Small apps with <1000 daily users
- Overlapping domains where context matters more than classification
- No training examples available

## API

### Defining Agents

Agents are just RubyLLM chat objects - use the same API you already know:

```ruby
my_agent = RubyLLM.chat(model: "claude-sonnet-4")
                  .with_instructions("You're a specialist...")
                  .with_tools(Tool1, Tool2)
                  .with_temperature(0.7)
```

### Router Options

```ruby
router = RubyLLM::SemanticRouter.new(
  agents: {
    product: product_chat,
    support: support_chat
  },
  default_agent: :product,

  # When confidence is below threshold, what to do?
  fallback: :default_agent,      # Use default (default)
  # fallback: :keep_current,     # Stay with current agent
  # fallback: :ask_clarification # Ask user to rephrase

  similarity_threshold: 0.7,     # 0.0-1.0, higher = stricter
  embedding_model: "text-embedding-3-small"
)
```

### Training

```ruby
# One at a time
router.add_example("Cancel my subscription", agent: :billing)

# Batch import (faster - single embedding API call)
router.import_examples([
  { text: "...", agent: :billing },
  { text: "...", agent: :support },
])
```

### Debugging

```ruby
# Preview routing without sending message
decision = router.match("test message")
decision.agent       # => :product
decision.confidence  # => 0.85

# See all matches and scores
router.debug_routing("test message")
# => {
#   message: "test message",
#   threshold: 0.7,
#   would_route_to: :product,
#   top_matches: [
#     { agent: :product, example: "show products", confidence: 0.85 },
#     { agent: :support, example: "help me", confidence: 0.42 }
#   ]
# }
```

### Conversation Flow

```ruby
router.ask("Show me phones")        # Routes to :product
router.current_agent                 # => :product

router.ask("Actually, I need help") # Routes to :support
router.current_agent                 # => :support

# Full history is preserved across agent switches
router.messages.size                 # => 4 (2 exchanges)
```

## How Agents Share Context

When the router switches agents, the new agent sees the **full conversation history** but with its own system prompt. This means:

1. Agent A responds with context
2. User asks something in Agent B's domain
3. Router switches to Agent B
4. Agent B sees the full chat, responds with its own expertise

The conversation flows naturally. Users don't notice the switch.

## Caveats

1. **You need training examples.** At least 5-10 per agent, more is better.

2. **Embeddings aren't magic.** "I want to return this" and "What's your return policy" are different intents. Train for both.

3. **Threshold tuning matters.** Start with 0.7, use `debug_routing` to see scores, adjust.

4. **Tool cycles are atomic.** If Agent A calls a tool, it keeps control until done. No mid-tool handoffs.

## Development

```bash
bundle install
bundle exec rspec
```

## License

MIT
