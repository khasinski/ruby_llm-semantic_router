# frozen_string_literal: true

RSpec.describe RubyLLM::SemanticRouter::Strategies::Semantic do
  let(:strategy) { described_class.new }

  let(:agents) do
    {
      product: RubyLLM::SemanticRouter::AgentConfig.new(
        name: :product,
        instructions: "Product specialist"
      ),
      account: RubyLLM::SemanticRouter::AgentConfig.new(
        name: :account,
        instructions: "Account manager"
      )
    }
  end

  let(:config) do
    RubyLLM::SemanticRouter::RouterConfig.new(
      embedding_model: "text-embedding-3-small",
      similarity_threshold: 0.5,
      k_neighbors: 3,
      fallback: :default_agent,
      default_agent: :product,
      scope: nil
    )
  end

  def create_example(text, agent_name)
    vectors = RubyLLM.embed(text, model: "test").vectors
    # Handle both single (returns vector directly) and batch (returns array of vectors)
    embedding = vectors.first.is_a?(Array) ? vectors.first : vectors
    RubyLLM::SemanticRouter::Router::InMemoryExample.new(
      agent_name: agent_name,
      example_text: text,
      embedding: embedding
    )
  end

  describe "#route" do
    context "with no examples" do
      it "returns fallback decision" do
        decision = strategy.route(
          "Any message",
          agents: agents,
          examples: [],
          current_agent: :product,
          config: config
        )

        expect(decision.reason).to eq(:fallback)
        expect(decision.agent).to eq(:product)
      end

      it "returns fallback for nil examples" do
        decision = strategy.route(
          "Any message",
          agents: agents,
          examples: nil,
          current_agent: :product,
          config: config
        )

        expect(decision.reason).to eq(:fallback)
      end
    end

    context "with examples" do
      let(:examples) do
        [
          create_example("Show me products", :product),
          create_example("Product catalog", :product),
          create_example("Change password", :account),
          create_example("Update email", :account)
        ]
      end

      it "routes to matching agent based on similarity" do
        # Use the exact same text as an example for guaranteed match
        decision = strategy.route(
          "Show me products",
          agents: agents,
          examples: examples,
          current_agent: :account,
          config: config
        )

        expect(decision.agent).to eq(:product)
        expect(decision.reason).to eq(:semantic_match)
        expect(decision.confidence).to be > 0
      end

      it "includes matched example in decision" do
        decision = strategy.route(
          "Show me products",
          agents: agents,
          examples: examples,
          current_agent: :product,
          config: config
        )

        expect(decision.matched_example).to eq("Show me products")
      end
    end

    context "with fallback behaviors" do
      let(:examples) { [] }

      it "uses default_agent fallback" do
        config_with_fallback = config.dup
        config_with_fallback.fallback = :default_agent

        decision = strategy.route(
          "Unclear message",
          agents: agents,
          examples: examples,
          current_agent: :account,
          config: config_with_fallback
        )

        expect(decision.agent).to eq(:product) # default agent
        expect(decision.reason).to eq(:fallback)
      end

      it "uses keep_current fallback" do
        config_with_fallback = config.dup
        config_with_fallback.fallback = :keep_current

        decision = strategy.route(
          "Unclear message",
          agents: agents,
          examples: examples,
          current_agent: :account,
          config: config_with_fallback
        )

        expect(decision.agent).to eq(:account) # kept current
        expect(decision.reason).to eq(:kept_current)
      end

      it "uses ask_clarification fallback" do
        config_with_fallback = config.dup
        config_with_fallback.fallback = :ask_clarification

        decision = strategy.route(
          "Unclear message",
          agents: agents,
          examples: examples,
          current_agent: :account,
          config: config_with_fallback
        )

        expect(decision.agent).to eq(:product) # default agent
        expect(decision.reason).to eq(:needs_clarification)
        expect(decision.inject_instruction).to include("clarify")
      end
    end

    context "with similarity threshold" do
      it "falls back when confidence is below threshold" do
        examples = [create_example("Very specific phrase xyz", :account)]

        high_threshold_config = config.dup
        high_threshold_config.similarity_threshold = 0.99

        decision = strategy.route(
          "Completely different message",
          agents: agents,
          examples: examples,
          current_agent: :product,
          config: high_threshold_config
        )

        expect(decision.fallback?).to be true
      end
    end
  end

  describe "cosine distance calculation" do
    it "correctly calculates cosine similarity" do
      # Same vectors should have distance 0
      examples = [create_example("test message", :product)]

      decision = strategy.route(
        "test message",
        agents: agents,
        examples: examples,
        current_agent: :product,
        config: config
      )

      expect(decision.confidence).to be_within(0.01).of(1.0)
    end
  end

  describe "custom find_examples" do
    it "uses custom search when find_examples is provided" do
      custom_search = ->(embedding, limit:) {
        [{ agent_name: :account, example_text: "Custom result", distance: 0.2 }]
      }

      decision = strategy.route(
        "any message",
        agents: agents,
        examples: [],
        current_agent: :product,
        config: config,
        find_examples: custom_search
      )

      expect(decision.agent).to eq(:account)
      expect(decision.matched_example).to eq("Custom result")
      expect(decision.confidence).to eq(0.8)
    end

    it "falls back when custom search returns nil" do
      custom_search = ->(embedding, limit:) { nil }

      decision = strategy.route(
        "any message",
        agents: agents,
        examples: [],
        current_agent: :product,
        config: config,
        find_examples: custom_search
      )

      expect(decision.fallback?).to be true
    end

    it "supports object results with methods" do
      result_object = Struct.new(:agent_name, :example_text, :distance).new(:product, "Object result", 0.15)
      custom_search = ->(embedding, limit:) { [result_object] }

      decision = strategy.route(
        "any message",
        agents: agents,
        examples: [],
        current_agent: :account,
        config: config,
        find_examples: custom_search
      )

      expect(decision.agent).to eq(:product)
      expect(decision.confidence).to eq(0.85)
    end

    it "converts score to distance" do
      custom_search = ->(embedding, limit:) {
        [{ agent_name: :product, score: 0.9 }]
      }

      decision = strategy.route(
        "any message",
        agents: agents,
        examples: [],
        current_agent: :account,
        config: config,
        find_examples: custom_search
      )

      expect(decision.confidence).to eq(0.9)
    end
  end
end
