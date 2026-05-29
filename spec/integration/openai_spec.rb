# frozen_string_literal: true

# Integration tests against real OpenAI API
# Run with: INTEGRATION=1 OPENAI_API_KEY=sk-... bundle exec rspec spec/integration/ --no-default-require

require "bundler/setup"
require "ruby_llm"
require "rubyllm/semantic_router"

RubyLLM.configure do |c|
  c.openai_api_key = ENV["OPENAI_API_KEY"]
end

RSpec.describe "OpenAI integration" do
  before(:each) do
    RubyLLM::SemanticRouter.reset_configuration!
  end

  describe "embedding generation" do
    it "generates single embedding" do
      response = RubyLLM.embed("hello world", model: "text-embedding-3-small")

      expect(response.vectors).to be_an(Array)
      expect(response.vectors.length).to eq(1536)
      expect(response.vectors.first).to be_a(Float)
    end

    it "generates batch embeddings" do
      response = RubyLLM.embed(["hello", "world"], model: "text-embedding-3-small")

      expect(response.vectors).to be_an(Array)
      expect(response.vectors.length).to eq(2)
      expect(response.vectors.first).to be_an(Array)
      expect(response.vectors.first.length).to eq(1536)
    end
  end

  describe "router end-to-end" do
    let(:router) do
      product_chat = RubyLLM.chat(model: "gpt-4o-mini")
                            .with_instructions("You are a product expert.")
      support_chat = RubyLLM.chat(model: "gpt-4o-mini")
                            .with_instructions("You are a support agent.")

      RubyLLM::SemanticRouter::Router.new(
        agents: { product: product_chat, support: support_chat },
        default_agent: :product,
        embedding_model: "text-embedding-3-small",
        similarity_threshold: 0.3
      )
    end

    before do
      router.import_examples([
        { text: "What laptops do you have?", agent: :product },
        { text: "Show me your best phones", agent: :product },
        { text: "What's the price of monitors?", agent: :product },
        { text: "I need help with my account", agent: :support },
        { text: "My order is broken", agent: :support },
        { text: "I can't log in", agent: :support }
      ])
    end

    it "routes product queries to product agent" do
      decision = router.match("What tablets do you sell?")

      expect(decision.agent).to eq(:product)
      expect(decision.reason).to eq(:semantic_match)
      expect(decision.confidence).to be > 0.3
    end

    it "routes support queries to support agent" do
      decision = router.match("I can't access my account")

      expect(decision.agent).to eq(:support)
      expect(decision.reason).to eq(:semantic_match)
      expect(decision.confidence).to be > 0.3
    end

    it "extracts config from chat objects correctly" do
      product_config = router.agent(:product)

      expect(product_config.instructions).to eq("You are a product expert.")
      expect(product_config.model).to eq("gpt-4o-mini")
    end

    it "sends message and gets response" do
      response = router.ask("What laptops do you have?")

      expect(response.content).to be_a(String)
      expect(response.content.length).to be > 0
    end

    it "batch routes messages" do
      decisions = router.ask_batch(["best headphones", "my package is lost"])

      expect(decisions.length).to eq(2)
      expect(decisions.map(&:agent)).to all(be_a(Symbol))
    end
  end
end
