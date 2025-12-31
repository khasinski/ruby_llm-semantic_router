# frozen_string_literal: true

module RubyLLM
  module SemanticRouter
    # Base error class for all semantic router errors
    class Error < StandardError; end

    # Raised when an agent name is not found in the router
    class AgentNotFoundError < Error
      def initialize(agent_name, available_agents)
        super("Agent '#{agent_name}' not found. Available agents: #{available_agents.join(', ')}")
      end
    end

    # Raised when no default agent is configured
    class NoDefaultAgentError < Error
      def initialize
        super("No default agent configured. Set default_agent when creating the router.")
      end
    end

    # Raised when no agents are configured
    class NoAgentsError < Error
      def initialize
        super("No agents configured. Add at least one agent to the router.")
      end
    end

    # Raised when routing examples are required but none exist
    class NoRoutingExamplesError < Error
      def initialize
        super("No routing examples found. Add examples using router.add_example or configure a fallback.")
      end
    end

    # Raised when embedding generation fails
    class EmbeddingError < Error
      def initialize(original_error)
        super("Failed to generate embedding: #{original_error.message}")
      end
    end

    # Raised when an invalid fallback behavior is specified
    class InvalidFallbackError < Error
      VALID_BEHAVIORS = %i[default_agent keep_current ask_clarification].freeze

      def initialize(behavior)
        super("Invalid fallback behavior '#{behavior}'. Valid options: #{VALID_BEHAVIORS.join(', ')}")
      end
    end

    # Raised when agent definition is incomplete
    class InvalidAgentError < Error
      def initialize(message)
        super("Invalid agent definition: #{message}")
      end
    end
  end
end
