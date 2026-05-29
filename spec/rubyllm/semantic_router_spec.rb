# frozen_string_literal: true

RSpec.describe RubyLLM::SemanticRouter do
  it "has a version number" do
    expect(RubyLLM::SemanticRouter::VERSION).not_to be nil
  end

  describe ".configure" do
    it "allows configuration via block" do
      described_class.configure do |config|
        config.default_embedding_model = "custom-model"
        config.default_similarity_threshold = 0.8
        config.default_k_neighbors = 5
        config.default_fallback = :keep_current
      end

      config = described_class.configuration

      expect(config.default_embedding_model).to eq("custom-model")
      expect(config.default_similarity_threshold).to eq(0.8)
      expect(config.default_k_neighbors).to eq(5)
      expect(config.default_fallback).to eq(:keep_current)
    end

    it "returns configuration object" do
      config = described_class.configure

      expect(config).to be_a(RubyLLM::SemanticRouter::Configuration)
    end
  end

  describe ".reset_configuration!" do
    it "resets to default values" do
      described_class.configure do |config|
        config.default_similarity_threshold = 0.99
      end

      described_class.reset_configuration!

      expect(described_class.configuration.default_similarity_threshold).to eq(0.3)
    end
  end

  describe "integration" do
    it "works end-to-end" do
      # Define agents as RubyLLM.chat objects
      agents = {
        product: RubyLLM.chat.with_instructions("You help with products"),
        account: RubyLLM.chat.with_instructions("You help with accounts")
      }

      router = RubyLLM::SemanticRouter.new(
        agents: agents,
        default_agent: :product,
        similarity_threshold: 0.5
      )

      # Add examples
      router.add_example("Show me the catalog", agent: :product)
      router.add_example("Change my password", agent: :account)

      # Route messages
      router.ask("Show me the catalog")
      expect(router.current_agent).to eq(:product)

      router.ask("Change my password")
      expect(router.current_agent).to eq(:account)

      # History is preserved
      expect(router.messages.size).to eq(4)
    end
  end
end
