# frozen_string_literal: true

RSpec.describe RubyLLM::SemanticRouter::EmbeddingCache do
  let(:cache) { described_class.new(ttl: 60) }

  describe "#get and #set" do
    it "stores and retrieves embeddings" do
      embedding = [0.1, 0.2, 0.3]
      cache.set("test key", embedding)

      expect(cache.get("test key")).to eq(embedding)
    end

    it "returns nil for missing keys" do
      expect(cache.get("nonexistent")).to be_nil
    end

    it "returns nil for expired entries" do
      cache = described_class.new(ttl: 0.01)
      cache.set("test", [1, 2, 3])

      sleep(0.02)

      expect(cache.get("test")).to be_nil
    end
  end

  describe "#fetch" do
    it "returns cached value without calling block" do
      cache.set("key", [1, 2, 3])
      block_called = false

      result = cache.fetch("key") do
        block_called = true
        [4, 5, 6]
      end

      expect(result).to eq([1, 2, 3])
      expect(block_called).to be false
    end

    it "calls block and caches result when key is missing" do
      result = cache.fetch("new_key") { [7, 8, 9] }

      expect(result).to eq([7, 8, 9])
      expect(cache.get("new_key")).to eq([7, 8, 9])
    end
  end

  describe "#cleanup!" do
    it "removes expired entries" do
      cache = described_class.new(ttl: 0.01)
      cache.set("expired", [1])
      sleep(0.02)
      cache.set("fresh", [2])

      cache.cleanup!

      expect(cache.get("expired")).to be_nil
      expect(cache.get("fresh")).to eq([2])
    end
  end

  describe "#clear!" do
    it "removes all entries" do
      cache.set("a", [1])
      cache.set("b", [2])

      cache.clear!

      expect(cache.size).to eq(0)
    end
  end

  describe "#size" do
    it "returns number of cached entries" do
      expect(cache.size).to eq(0)

      cache.set("a", [1])
      cache.set("b", [2])

      expect(cache.size).to eq(2)
    end
  end

  describe "thread safety" do
    it "handles concurrent access" do
      threads = 10.times.map do |i|
        Thread.new do
          100.times do |j|
            key = "key_#{i}_#{j}"
            cache.set(key, [i, j])
            cache.get(key)
          end
        end
      end

      threads.each(&:join)
      expect(cache.size).to be > 0
    end
  end
end
