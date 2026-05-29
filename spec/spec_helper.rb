# frozen_string_literal: true

require "bundler/setup"
require "rubyllm/semantic_router"

# Skip mocks for integration tests (they use the real API)
return if ENV["INTEGRATION"]

# Mock RubyLLM for testing without actual API calls
module RubyLLM
  class << self
    def embed(input, model:)
      # Return a mock embedding response
      # Supports both single text and array of texts
      MockEmbeddingResponse.new(input)
    end

    def chat(**options)
      MockChat.new(**options)
    end
  end

  class MockEmbeddingResponse
    attr_reader :input

    def initialize(input)
      @input = input
    end

    # Generate deterministic embeddings based on text content
    # Matches real RubyLLM behavior:
    # - Single text: returns vector directly
    # - Array of texts: returns array of vectors
    def vectors
      if @input.is_a?(Array)
        @input.map { |text| generate_mock_embedding(text) }
      else
        generate_mock_embedding(@input)
      end
    end

    private

    def generate_mock_embedding(text)
      # Simple hash-based mock embedding (128 dimensions)
      hash = text.to_s.downcase.gsub(/[^a-z0-9]/, '').chars.map(&:ord).sum
      Array.new(128) { |i| Math.sin(hash + i) * 0.5 }
    end
  end

  class MockChat
    attr_reader :messages, :instructions, :tools, :model_id, :temperature_value

    def initialize(**options)
      @messages = []
      @instructions = nil
      @tools = []
      @model_id = options[:model]
      @temperature_value = nil
    end

    def with_instructions(text, replace: false)
      @instructions = text
      self
    end

    def with_tools(*tools, replace: false)
      @tools = replace ? tools : @tools + tools
      self
    end

    def with_model(model)
      @model_id = model
      self
    end

    def with_temperature(temp)
      @temperature_value = temp
      self
    end

    def ask(message, &block)
      @messages << MockMessage.new(role: :user, content: message)
      response = MockMessage.new(role: :assistant, content: "Mock response to: #{message}")
      @messages << response

      if block
        block.call(MockChunk.new(response.content))
      end

      response
    end
  end

  class MockMessage
    attr_reader :role, :content

    def initialize(role:, content:)
      @role = role
      @content = content
    end
  end

  class MockChunk
    attr_reader :content

    def initialize(content)
      @content = content
    end
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do
    RubyLLM::SemanticRouter.reset_configuration!
  end
end
