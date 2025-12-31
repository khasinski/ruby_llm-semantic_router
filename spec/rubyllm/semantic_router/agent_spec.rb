# frozen_string_literal: true

RSpec.describe RubyLLM::SemanticRouter::Agent do
  describe ".new" do
    it "creates an agent with required attributes" do
      agent = described_class.new(
        name: :product,
        instructions: "You are a product specialist"
      )

      expect(agent.name).to eq(:product)
      expect(agent.instructions).to eq("You are a product specialist")
      expect(agent.tools).to eq([])
      expect(agent.model).to be_nil
    end

    it "accepts optional attributes" do
      class FakeTool; end

      agent = described_class.new(
        name: "account",
        instructions: "Account manager",
        tools: [FakeTool],
        model: "claude-sonnet-4",
        temperature: 0.7
      )

      expect(agent.name).to eq(:account)
      expect(agent.tools).to eq([FakeTool])
      expect(agent.model).to eq("claude-sonnet-4")
      expect(agent.temperature).to eq(0.7)
    end

    it "converts name to symbol" do
      agent = described_class.new(name: "product", instructions: "test")
      expect(agent.name).to eq(:product)
    end

    it "raises error when name is missing" do
      expect {
        described_class.new(name: nil, instructions: "test")
      }.to raise_error(RubyLLM::SemanticRouter::InvalidAgentError, /name is required/)
    end

    it "raises error when instructions are missing" do
      expect {
        described_class.new(name: :test, instructions: nil)
      }.to raise_error(RubyLLM::SemanticRouter::InvalidAgentError, /instructions are required/)
    end
  end

  describe ".define" do
    it "creates an agent using DSL" do
      agent = described_class.define do
        name :support
        instructions "You provide customer support"
        model "gpt-4"
        temperature 0.5
      end

      expect(agent.name).to eq(:support)
      expect(agent.instructions).to eq("You provide customer support")
      expect(agent.model).to eq("gpt-4")
      expect(agent.temperature).to eq(0.5)
    end

    it "allows adding multiple tools" do
      class Tool1; end
      class Tool2; end

      agent = described_class.define do
        name :multi_tool
        instructions "Has multiple tools"
        tools Tool1, Tool2
      end

      expect(agent.tools).to eq([Tool1, Tool2])
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      agent = described_class.new(
        name: :product,
        instructions: "Product specialist",
        model: "claude-sonnet-4"
      )

      hash = agent.to_h

      expect(hash[:name]).to eq(:product)
      expect(hash[:instructions]).to eq("Product specialist")
      expect(hash[:model]).to eq("claude-sonnet-4")
      expect(hash[:tools]).to eq([])
    end
  end
end
