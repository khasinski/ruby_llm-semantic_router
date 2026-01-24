# frozen_string_literal: true

RSpec.describe RubyLLM::SemanticRouter::Configuration do
  let(:config) { described_class.new }

  describe "default values" do
    it "sets default embedding model" do
      expect(config.default_embedding_model).to eq("text-embedding-3-small")
    end

    it "sets default similarity threshold" do
      expect(config.default_similarity_threshold).to eq(0.7)
    end

    it "sets default k_neighbors" do
      expect(config.default_k_neighbors).to eq(3)
    end

    it "sets default fallback" do
      expect(config.default_fallback).to eq(:default_agent)
    end

    it "sets default max_words to nil" do
      expect(config.default_max_words).to be_nil
    end
  end

  describe "#default_similarity_threshold=" do
    it "accepts valid threshold values" do
      config.default_similarity_threshold = 0.0
      expect(config.default_similarity_threshold).to eq(0.0)

      config.default_similarity_threshold = 0.5
      expect(config.default_similarity_threshold).to eq(0.5)

      config.default_similarity_threshold = 1.0
      expect(config.default_similarity_threshold).to eq(1.0)
    end

    it "accepts float-like integers" do
      config.default_similarity_threshold = 0
      expect(config.default_similarity_threshold).to eq(0)

      config.default_similarity_threshold = 1
      expect(config.default_similarity_threshold).to eq(1)
    end

    it "raises error for threshold below 0" do
      expect {
        config.default_similarity_threshold = -0.1
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /between 0.0 and 1.0/)
    end

    it "raises error for threshold above 1" do
      expect {
        config.default_similarity_threshold = 1.1
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /between 0.0 and 1.0/)
    end

    it "raises error for non-numeric values" do
      expect {
        config.default_similarity_threshold = "0.5"
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /between 0.0 and 1.0/)

      expect {
        config.default_similarity_threshold = nil
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /between 0.0 and 1.0/)
    end
  end

  describe "#default_k_neighbors=" do
    it "accepts positive integers" do
      config.default_k_neighbors = 1
      expect(config.default_k_neighbors).to eq(1)

      config.default_k_neighbors = 10
      expect(config.default_k_neighbors).to eq(10)
    end

    it "raises error for zero" do
      expect {
        config.default_k_neighbors = 0
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /positive integer/)
    end

    it "raises error for negative values" do
      expect {
        config.default_k_neighbors = -1
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /positive integer/)
    end

    it "raises error for non-integer values" do
      expect {
        config.default_k_neighbors = 3.5
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /positive integer/)

      expect {
        config.default_k_neighbors = "3"
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /positive integer/)
    end
  end

  describe "#default_max_words=" do
    it "accepts nil" do
      config.default_max_words = nil
      expect(config.default_max_words).to be_nil
    end

    it "accepts positive integers" do
      config.default_max_words = 1
      expect(config.default_max_words).to eq(1)

      config.default_max_words = 100
      expect(config.default_max_words).to eq(100)
    end

    it "raises error for zero" do
      expect {
        config.default_max_words = 0
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /nil or a positive integer/)
    end

    it "raises error for negative values" do
      expect {
        config.default_max_words = -5
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /nil or a positive integer/)
    end

    it "raises error for non-integer values" do
      expect {
        config.default_max_words = 10.5
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /nil or a positive integer/)
    end
  end

  describe "#default_fallback=" do
    it "accepts valid fallback symbols" do
      config.default_fallback = :default_agent
      expect(config.default_fallback).to eq(:default_agent)

      config.default_fallback = :keep_current
      expect(config.default_fallback).to eq(:keep_current)

      config.default_fallback = :ask_clarification
      expect(config.default_fallback).to eq(:ask_clarification)
    end

    it "raises error for invalid fallback values" do
      expect {
        config.default_fallback = :invalid
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /default_agent, keep_current, ask_clarification/)

      expect {
        config.default_fallback = "default_agent"
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError)

      expect {
        config.default_fallback = nil
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError)
    end
  end
end

RSpec.describe "Router configuration validation" do
  let(:agents) do
    {
      product: RubyLLM.chat.with_instructions("Product help"),
      support: RubyLLM.chat.with_instructions("Support help")
    }
  end

  it "raises error for invalid similarity_threshold" do
    expect {
      RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product,
        similarity_threshold: 1.5
      )
    }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /similarity_threshold/)
  end

  it "raises error for invalid k_neighbors" do
    expect {
      RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product,
        k_neighbors: 0
      )
    }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /k_neighbors/)
  end

  it "raises error for invalid max_words" do
    expect {
      RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product,
        max_words: -1
      )
    }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /max_words/)
  end

  it "raises error for invalid fallback" do
    expect {
      RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product,
        fallback: :unknown
      )
    }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError, /fallback/)
  end

  it "accepts valid edge case values" do
    # Boundary values should work
    router = RubyLLM::SemanticRouter::Router.new(
      agents: agents,
      default_agent: :product,
      similarity_threshold: 0.0,
      k_neighbors: 1,
      max_words: 1
    )

    expect(router).to be_a(RubyLLM::SemanticRouter::Router)
  end
end
