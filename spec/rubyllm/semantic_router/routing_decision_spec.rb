# frozen_string_literal: true

RSpec.describe RubyLLM::SemanticRouter::RoutingDecision do
  describe ".new" do
    it "creates a decision with default values" do
      decision = described_class.new(agent: :product)

      expect(decision.agent).to eq(:product)
      expect(decision.confidence).to eq(0.0)
      expect(decision.matched_example).to be_nil
      expect(decision.reason).to eq(:semantic_match)
      expect(decision.inject_instruction).to be_nil
    end

    it "accepts all attributes" do
      decision = described_class.new(
        agent: "account",
        confidence: 0.85,
        matched_example: "Change my password",
        reason: :semantic_match,
        inject_instruction: nil
      )

      expect(decision.agent).to eq(:account)
      expect(decision.confidence).to eq(0.85)
      expect(decision.matched_example).to eq("Change my password")
    end

    it "converts agent to symbol" do
      decision = described_class.new(agent: "product")
      expect(decision.agent).to eq(:product)
    end
  end

  describe "#confident?" do
    it "returns true for semantic match with confidence > 0" do
      decision = described_class.new(
        agent: :product,
        confidence: 0.8,
        reason: :semantic_match
      )

      expect(decision.confident?).to be true
    end

    it "returns false for fallback decisions" do
      decision = described_class.new(
        agent: :product,
        confidence: 0.0,
        reason: :fallback
      )

      expect(decision.confident?).to be false
    end

    it "returns false for zero confidence" do
      decision = described_class.new(
        agent: :product,
        confidence: 0,
        reason: :semantic_match
      )

      expect(decision.confident?).to be false
    end
  end

  describe "#fallback?" do
    it "returns true for fallback reason" do
      decision = described_class.new(agent: :default, reason: :fallback)
      expect(decision.fallback?).to be true
    end

    it "returns true for kept_current reason" do
      decision = described_class.new(agent: :current, reason: :kept_current)
      expect(decision.fallback?).to be true
    end

    it "returns true for needs_clarification reason" do
      decision = described_class.new(agent: :default, reason: :needs_clarification)
      expect(decision.fallback?).to be true
    end

    it "returns false for semantic_match reason" do
      decision = described_class.new(agent: :product, reason: :semantic_match)
      expect(decision.fallback?).to be false
    end
  end

  describe "#needs_clarification?" do
    it "returns true when reason is needs_clarification" do
      decision = described_class.new(
        agent: :default,
        reason: :needs_clarification,
        inject_instruction: "Please clarify"
      )

      expect(decision.needs_clarification?).to be true
    end

    it "returns false for other reasons" do
      decision = described_class.new(agent: :product, reason: :semantic_match)
      expect(decision.needs_clarification?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      decision = described_class.new(
        agent: :product,
        confidence: 0.9,
        matched_example: "Show products"
      )

      hash = decision.to_h

      expect(hash[:agent]).to eq(:product)
      expect(hash[:confidence]).to eq(0.9)
      expect(hash[:matched_example]).to eq("Show products")
      expect(hash[:reason]).to eq(:semantic_match)
    end

    it "excludes nil values" do
      decision = described_class.new(agent: :product)
      hash = decision.to_h

      expect(hash).not_to have_key(:matched_example)
      expect(hash).not_to have_key(:inject_instruction)
    end
  end

  describe "#==" do
    it "returns true for equal decisions" do
      decision1 = described_class.new(agent: :product, confidence: 0.9, reason: :semantic_match)
      decision2 = described_class.new(agent: :product, confidence: 0.9, reason: :semantic_match)

      expect(decision1).to eq(decision2)
    end

    it "returns false for different agents" do
      decision1 = described_class.new(agent: :product)
      decision2 = described_class.new(agent: :account)

      expect(decision1).not_to eq(decision2)
    end
  end
end
