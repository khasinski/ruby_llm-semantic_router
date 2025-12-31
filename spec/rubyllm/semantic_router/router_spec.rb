# frozen_string_literal: true

RSpec.describe RubyLLM::SemanticRouter::Router do
  let(:agents) do
    {
      product: RubyLLM.chat(model: "claude-sonnet-4")
                      .with_instructions("You are a product specialist. Help users find products."),
      account: RubyLLM.chat
                      .with_instructions("You help users manage their accounts."),
      general: RubyLLM.chat
                      .with_instructions("You are a helpful general assistant.")
    }
  end

  describe ".new" do
    it "creates a router with agents and default agent" do
      router = described_class.new(
        agents: agents,
        default_agent: :general
      )

      expect(router.agent_names).to contain_exactly(:product, :account, :general)
      expect(router.current_agent).to eq(:general)
    end

    it "raises error when default agent is not in agents list" do
      expect {
        described_class.new(
          agents: agents,
          default_agent: :unknown
        )
      }.to raise_error(RubyLLM::SemanticRouter::AgentNotFoundError, /unknown/)
    end

    it "raises error when instructions missing" do
      expect {
        described_class.new(
          agents: { broken: RubyLLM.chat(model: "gpt-4") },
          default_agent: :broken
        )
      }.to raise_error(RubyLLM::SemanticRouter::InvalidAgentError, /instructions/)
    end

    it "uses global configuration defaults" do
      RubyLLM::SemanticRouter.configure do |config|
        config.default_similarity_threshold = 0.8
        config.default_fallback = :keep_current
      end

      router = described_class.new(
        agents: agents,
        default_agent: :general
      )

      expect(router).to be_a(described_class)
    end

    it "allows overriding global configuration" do
      router = described_class.new(
        agents: agents,
        default_agent: :general,
        similarity_threshold: 0.9,
        fallback: :ask_clarification,
        embedding_model: "custom-model"
      )

      expect(router).to be_a(described_class)
    end
  end

  describe "#add_example" do
    let(:router) do
      described_class.new(agents: agents, default_agent: :general)
    end

    it "adds a routing example" do
      router.add_example("What products do you have?", agent: :product)

      expect(router.examples.size).to eq(1)
      expect(router.examples.first.agent_name).to eq(:product)
      expect(router.examples.first.example_text).to eq("What products do you have?")
    end

    it "raises error for unknown agent" do
      expect {
        router.add_example("Test", agent: :unknown)
      }.to raise_error(RubyLLM::SemanticRouter::AgentNotFoundError)
    end

    it "returns self for chaining" do
      result = router.add_example("Test", agent: :product)
      expect(result).to eq(router)
    end
  end

  describe "#import_examples" do
    let(:router) do
      described_class.new(agents: agents, default_agent: :general)
    end

    it "imports multiple examples at once" do
      router.import_examples([
        { text: "Show products", agent: :product },
        { text: "Change password", agent: :account },
        { text: "General help", agent: :general }
      ])

      expect(router.examples.size).to eq(3)
    end

    it "validates all agents before importing" do
      expect {
        router.import_examples([
          { text: "Valid", agent: :product },
          { text: "Invalid", agent: :unknown }
        ])
      }.to raise_error(RubyLLM::SemanticRouter::AgentNotFoundError)
    end

    it "handles empty array" do
      router.import_examples([])
      expect(router.examples).to be_empty
    end
  end

  describe "#match" do
    let(:router) do
      described_class.new(agents: agents, default_agent: :general)
    end

    before do
      router.add_example("Show me products", agent: :product)
    end

    it "returns routing decision without sending message" do
      decision = router.match("Show me products")

      expect(decision).to be_a(RubyLLM::SemanticRouter::RoutingDecision)
      expect(decision.agent).to eq(:product)
      expect(router.messages).to be_empty
    end
  end

  describe "#debug_routing" do
    let(:router) do
      described_class.new(agents: agents, default_agent: :general)
    end

    before do
      router.import_examples([
        { text: "Show products", agent: :product },
        { text: "Product catalog", agent: :product },
        { text: "Change password", agent: :account }
      ])
    end

    it "returns detailed routing information" do
      debug_info = router.debug_routing("Show products")

      expect(debug_info[:message]).to eq("Show products")
      expect(debug_info[:threshold]).to eq(0.7)
      expect(debug_info[:would_route_to]).to eq(:product)
      expect(debug_info[:top_matches]).to be_an(Array)
      expect(debug_info[:top_matches].first[:agent]).to eq(:product)
      expect(debug_info[:top_matches].first[:confidence]).to be_a(Float)
    end
  end

  describe "#ask" do
    let(:router) do
      described_class.new(
        agents: agents,
        default_agent: :general,
        similarity_threshold: 0.5
      )
    end

    before do
      router.add_example("Show me products", agent: :product)
      router.add_example("Product catalog", agent: :product)
      router.add_example("Change my password", agent: :account)
      router.add_example("Update my email", agent: :account)
    end

    it "routes to the appropriate agent and returns response" do
      response = router.ask("Show me products")

      expect(response).to be_a(RubyLLM::MockMessage)
      expect(response.content).to include("Mock response")
    end

    it "tracks routing decision" do
      router.ask("Show me products")

      expect(router.last_routing_decision).to be_a(RubyLLM::SemanticRouter::RoutingDecision)
      expect(router.last_routing_decision.agent).to eq(:product)
    end

    it "switches agent when routing to a different one" do
      expect(router.current_agent).to eq(:general)

      router.ask("Show me products")

      expect(router.current_agent).to eq(:product)
    end

    it "preserves message history across agent switches" do
      router.ask("Show me products")
      router.ask("Change my password")

      expect(router.messages.size).to eq(4)
      expect(router.current_agent).to eq(:account)
    end

    it "supports streaming" do
      chunks = []
      router.ask("Show me products") do |chunk|
        chunks << chunk
      end

      expect(chunks).not_to be_empty
    end

    it "falls back to default agent when no match" do
      router.clear_examples!

      router.ask("Random message")

      expect(router.current_agent).to eq(:general)
      expect(router.last_routing_decision.fallback?).to be true
    end
  end

  describe "#switch_to" do
    let(:router) do
      described_class.new(agents: agents, default_agent: :general)
    end

    it "manually switches to specified agent" do
      router.switch_to(:product)

      expect(router.current_agent).to eq(:product)
    end

    it "accepts string agent names" do
      router.switch_to("account")

      expect(router.current_agent).to eq(:account)
    end

    it "raises error for unknown agent" do
      expect {
        router.switch_to(:unknown)
      }.to raise_error(RubyLLM::SemanticRouter::AgentNotFoundError)
    end

    it "does nothing when switching to current agent" do
      router.switch_to(:general)
      router.switch_to(:general)

      expect(router.current_agent).to eq(:general)
    end
  end

  describe "#agent" do
    let(:router) do
      described_class.new(agents: agents, default_agent: :general)
    end

    it "returns agent config by name" do
      agent = router.agent(:product)

      expect(agent.name).to eq(:product)
      expect(agent.instructions).to eq("You are a product specialist. Help users find products.")
      expect(agent.model).to eq("claude-sonnet-4")
    end

    it "accepts string names" do
      agent = router.agent("product")

      expect(agent.name).to eq(:product)
    end
  end

  describe "#clear_examples!" do
    let(:router) do
      described_class.new(agents: agents, default_agent: :general)
    end

    it "removes all examples" do
      router.add_example("Test", agent: :product)
      router.clear_examples!

      expect(router.examples).to be_empty
    end
  end

  describe "#with_examples" do
    let(:router) do
      described_class.new(agents: agents, default_agent: :general)
    end

    it "sets external examples source" do
      external_source = []
      router.with_examples(external_source)

      expect(router.examples).to eq(external_source)
    end
  end

  describe "#on" do
    let(:router) do
      described_class.new(agents: agents, default_agent: :general)
    end

    it "registers callback for routing events" do
      routing_decisions = []

      router.on(:on_route) { |decision| routing_decisions << decision }
      router.add_example("Products", agent: :product)
      router.ask("Products")

      expect(routing_decisions.size).to eq(1)
      expect(routing_decisions.first).to be_a(RubyLLM::SemanticRouter::RoutingDecision)
    end
  end

  describe "scoped examples" do
    it "filters examples by scope when configured" do
      scoped_router = described_class.new(
        agents: agents,
        default_agent: :general,
        scope: "tenant_1"
      )

      scoped_router.add_example("Products", agent: :product)

      expect(scoped_router.examples.size).to eq(1)
    end
  end
end
