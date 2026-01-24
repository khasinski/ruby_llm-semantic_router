# frozen_string_literal: true

RSpec.describe RubyLLM::SemanticRouter::Utils do
  describe ".cosine_distance" do
    it "returns 0 for identical vectors" do
      vector = [1.0, 0.0, 0.0]
      expect(described_class.cosine_distance(vector, vector)).to be_within(0.0001).of(0.0)
    end

    it "returns 2 for opposite vectors" do
      v1 = [1.0, 0.0, 0.0]
      v2 = [-1.0, 0.0, 0.0]
      expect(described_class.cosine_distance(v1, v2)).to be_within(0.0001).of(2.0)
    end

    it "returns 1 for orthogonal vectors" do
      v1 = [1.0, 0.0]
      v2 = [0.0, 1.0]
      expect(described_class.cosine_distance(v1, v2)).to be_within(0.0001).of(1.0)
    end

    it "handles zero vectors by returning 1.0" do
      zero = [0.0, 0.0, 0.0]
      v1 = [1.0, 2.0, 3.0]

      expect(described_class.cosine_distance(zero, v1)).to eq(1.0)
      expect(described_class.cosine_distance(v1, zero)).to eq(1.0)
      expect(described_class.cosine_distance(zero, zero)).to eq(1.0)
    end

    it "works with large dimension vectors" do
      v1 = Array.new(1536) { rand }
      # Same vector should have distance ~0
      expect(described_class.cosine_distance(v1, v1)).to be_within(0.0001).of(0.0)
    end

    it "returns values in range [0, 2]" do
      100.times do
        v1 = Array.new(128) { rand(-1.0..1.0) }
        v2 = Array.new(128) { rand(-1.0..1.0) }
        distance = described_class.cosine_distance(v1, v2)

        expect(distance).to be >= 0.0
        expect(distance).to be <= 2.0
      end
    end
  end

  describe ".cosine_similarity" do
    it "returns 1 for identical vectors" do
      vector = [1.0, 0.0, 0.0]
      expect(described_class.cosine_similarity(vector, vector)).to be_within(0.0001).of(1.0)
    end

    it "returns -1 for opposite vectors" do
      v1 = [1.0, 0.0, 0.0]
      v2 = [-1.0, 0.0, 0.0]
      expect(described_class.cosine_similarity(v1, v2)).to be_within(0.0001).of(-1.0)
    end

    it "returns 0 for orthogonal vectors" do
      v1 = [1.0, 0.0]
      v2 = [0.0, 1.0]
      expect(described_class.cosine_similarity(v1, v2)).to be_within(0.0001).of(0.0)
    end
  end

  describe ".truncate_to_max_words" do
    it "returns text unchanged when max_words is nil" do
      text = "one two three four five"
      expect(described_class.truncate_to_max_words(text, nil)).to eq(text)
    end

    it "returns text unchanged when word count is at limit" do
      text = "one two three"
      expect(described_class.truncate_to_max_words(text, 3)).to eq(text)
    end

    it "returns text unchanged when word count is below limit" do
      text = "one two"
      expect(described_class.truncate_to_max_words(text, 5)).to eq(text)
    end

    it "truncates text when word count exceeds limit" do
      text = "one two three four five six"
      expect(described_class.truncate_to_max_words(text, 3)).to eq("one two three")
    end

    it "handles single word with max_words = 1" do
      text = "hello world"
      expect(described_class.truncate_to_max_words(text, 1)).to eq("hello")
    end

    it "handles empty string" do
      expect(described_class.truncate_to_max_words("", 5)).to eq("")
    end

    it "handles text with multiple spaces" do
      text = "one  two   three    four"
      result = described_class.truncate_to_max_words(text, 2)
      expect(result).to eq("one two")
    end

    it "preserves newlines in truncated text" do
      text = "one\ntwo\nthree\nfour\nfive"
      result = described_class.truncate_to_max_words(text, 3)
      expect(result).to eq("one two three")
    end
  end
end
