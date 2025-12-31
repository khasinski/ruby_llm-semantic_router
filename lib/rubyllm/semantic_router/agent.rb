# frozen_string_literal: true

module RubyLLM
  module SemanticRouter
    # Represents a specialized agent with its own system prompt, tools, and model
    class Agent
      attr_reader :name, :instructions, :tools, :model, :temperature

      def initialize(name:, instructions:, tools: [], model: nil, temperature: nil)
        # Validate before assignment to provide clear errors
        raise InvalidAgentError, "name is required" if name.nil? || name.to_s.empty?
        raise InvalidAgentError, "instructions are required" if instructions.nil? || instructions.to_s.empty?

        @name = name.to_sym
        @instructions = instructions
        @tools = Array(tools)
        @model = model
        @temperature = temperature
      end

      # DSL for defining agents
      #
      # @example
      #   ProductAgent = RubyLLM::SemanticRouter::Agent.define do
      #     name :product
      #     instructions "You are a product specialist..."
      #     model "claude-sonnet-4"
      #     tools ProductSearch, PriceCheck
      #   end
      def self.define(&block)
        builder = AgentBuilder.new
        builder.instance_eval(&block)
        builder.build
      end

      def to_h
        {
          name: name,
          instructions: instructions,
          tools: tools.map { |t| t.is_a?(Class) ? t.name : t.class.name },
          model: model,
          temperature: temperature
        }.compact
      end

    end

    # Builder for the Agent DSL
    class AgentBuilder
      def initialize
        @name = nil
        @instructions = nil
        @tools = []
        @model = nil
        @temperature = nil
      end

      def name(value = nil)
        @name = value if value
        @name
      end

      def instructions(value = nil)
        @instructions = value if value
        @instructions
      end

      def tools(*values)
        @tools.concat(values.flatten) if values.any?
        @tools
      end

      def model(value = nil)
        @model = value if value
        @model
      end

      def temperature(value = nil)
        @temperature = value if value
        @temperature
      end

      def build
        Agent.new(
          name: @name,
          instructions: @instructions,
          tools: @tools,
          model: @model,
          temperature: @temperature
        )
      end
    end
  end
end
