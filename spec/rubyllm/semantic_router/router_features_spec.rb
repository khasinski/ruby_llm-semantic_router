# frozen_string_literal: true

require "logger"
require "stringio"

RSpec.describe "Router Advanced Features" do
  let(:agents) do
    {
      product: RubyLLM.chat.with_instructions("Product expert"),
      support: RubyLLM.chat.with_instructions("Support agent")
    }
  end

  describe "logging" do
    let(:log_output) { StringIO.new }
    let(:logger) { Logger.new(log_output) }

    it "logs routing decisions when logger is configured" do
      router = RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product,
        logger: logger
      )

      router.add_example("Show products", agent: :product)
      router.ask("Show products")

      log_output.rewind
      logs = log_output.read

      expect(logs).to include("SemanticRouter")
      expect(logs).to include("Routed to")
    end

    it "uses global logger configuration" do
      RubyLLM::SemanticRouter.configure do |config|
        config.logger = logger
      end

      router = RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product
      )

      router.add_example("Test", agent: :product)
      router.ask("Test")

      log_output.rewind
      expect(log_output.read).to include("SemanticRouter")
    end

    it "does not log when logger is nil" do
      router = RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product,
        logger: nil
      )

      # Should not raise any errors
      router.add_example("Test", agent: :product)
      expect { router.ask("Test") }.not_to raise_error
    end
  end

  describe "embedding cache" do
    it "caches embeddings when cache_ttl is set" do
      embed_call_count = 0
      original_embed = RubyLLM.method(:embed)

      allow(RubyLLM).to receive(:embed) do |*args, **kwargs|
        embed_call_count += 1
        original_embed.call(*args, **kwargs)
      end

      router = RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product,
        cache_ttl: 60
      )

      # First add_example call generates embedding
      router.add_example("Cached text", agent: :product)
      first_count = embed_call_count

      # Clear examples and add same text again - should use cache
      router.clear_examples!
      router.add_example("Cached text", agent: :product)
      second_count = embed_call_count

      # Second add_example with same text should use cached embedding
      expect(second_count).to eq(first_count)
    end

    it "exposes embedding_cache accessor" do
      router = RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product,
        cache_ttl: 60
      )

      expect(router.embedding_cache).to be_a(RubyLLM::SemanticRouter::EmbeddingCache)
    end

    it "has nil cache when cache_ttl is not set" do
      router = RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product
      )

      expect(router.embedding_cache).to be_nil
    end
  end

  describe "#ask_batch" do
    let(:router) do
      r = RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product
      )
      r.add_example("Product info", agent: :product)
      r.add_example("Help with issues", agent: :support)
      r
    end

    it "routes multiple messages and returns decisions" do
      messages = ["Product info", "Help with issues", "Unknown message"]
      decisions = router.ask_batch(messages)

      expect(decisions.size).to eq(3)
      expect(decisions).to all(be_a(RubyLLM::SemanticRouter::RoutingDecision))
    end

    it "returns correct agents for each message" do
      decisions = router.ask_batch(["Product info", "Help with issues"])

      expect(decisions[0].agent).to eq(:product)
      expect(decisions[1].agent).to eq(:support)
    end

    it "emits on_route callback for each message" do
      routed_decisions = []
      router.on(:on_route) { |d| routed_decisions << d }

      router.ask_batch(["Message 1", "Message 2"])

      expect(routed_decisions.size).to eq(2)
    end

    it "handles empty message array" do
      decisions = router.ask_batch([])
      expect(decisions).to eq([])
    end
  end

  describe "retry logic" do
    it "retries on embedding failure" do
      call_count = 0
      allow(RubyLLM).to receive(:embed) do |*args, **kwargs|
        call_count += 1
        if call_count < 2
          raise StandardError, "Temporary failure"
        end
        RubyLLM::MockEmbeddingResponse.new(args.first)
      end

      router = RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product,
        max_retries: 3,
        retry_base_delay: 0.01
      )

      # Should succeed after retry
      expect { router.add_example("Test", agent: :product) }.not_to raise_error
      expect(call_count).to eq(2)
    end

    it "raises after max retries exceeded" do
      allow(RubyLLM).to receive(:embed).and_raise(StandardError, "Persistent failure")

      router = RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product,
        max_retries: 2,
        retry_base_delay: 0.01
      )

      expect {
        router.add_example("Test", agent: :product)
      }.to raise_error(RubyLLM::SemanticRouter::EmbeddingError)
    end

    it "uses exponential backoff" do
      delays = []
      allow_any_instance_of(RubyLLM::SemanticRouter::Router).to receive(:sleep) do |_, delay|
        delays << delay
      end

      call_count = 0
      allow(RubyLLM).to receive(:embed) do |*args, **kwargs|
        call_count += 1
        if call_count <= 3
          raise StandardError, "Failure #{call_count}"
        end
        RubyLLM::MockEmbeddingResponse.new(args.first)
      end

      router = RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product,
        max_retries: 3,
        retry_base_delay: 0.1
      )

      router.add_example("Test", agent: :product)

      # Exponential backoff: 0.1, 0.2, 0.4
      expect(delays[0]).to be_within(0.01).of(0.1)
      expect(delays[1]).to be_within(0.01).of(0.2)
      expect(delays[2]).to be_within(0.01).of(0.4)
    end
  end

  describe "global configuration" do
    after do
      RubyLLM::SemanticRouter.reset_configuration!
    end

    it "uses global cache_ttl" do
      RubyLLM::SemanticRouter.configure do |config|
        config.cache_ttl = 120
      end

      router = RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product
      )

      expect(router.embedding_cache).not_to be_nil
    end

    it "uses global max_retries" do
      RubyLLM::SemanticRouter.configure do |config|
        config.max_retries = 5
      end

      router = RubyLLM::SemanticRouter::Router.new(
        agents: agents,
        default_agent: :product
      )

      # Access internal state to verify
      expect(router.instance_variable_get(:@max_retries)).to eq(5)
    end

    it "validates cache_ttl" do
      expect {
        RubyLLM::SemanticRouter.configure do |config|
          config.cache_ttl = -1
        end
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError)
    end

    it "validates max_retries" do
      expect {
        RubyLLM::SemanticRouter.configure do |config|
          config.max_retries = -1
        end
      }.to raise_error(RubyLLM::SemanticRouter::ConfigurationError)
    end
  end
end
