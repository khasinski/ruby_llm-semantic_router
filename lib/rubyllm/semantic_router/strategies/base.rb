# frozen_string_literal: true

module RubyLLM
  module SemanticRouter
    module Strategies
      # Base class for routing strategies
      #
      # Subclasses must implement the #route method which receives:
      # - message: The user's message to route
      # - agents: Hash of agent_name => Agent objects
      # - examples: The routing examples (ActiveRecord relation or array)
      # - current_agent: The currently active agent name (symbol)
      # - config: RouterConfig with threshold, fallback, etc.
      #
      # The #route method should return a RoutingDecision object
      class Base
        def route(message, agents:, examples:, current_agent:, config:)
          raise NotImplementedError, "Subclasses must implement #route"
        end

        protected

        # Apply fallback behavior based on configuration
        #
        # @param config [RouterConfig] Router configuration
        # @param current_agent [Symbol] Currently active agent
        # @param default_agent [Symbol] Default agent from router
        # @return [RoutingDecision]
        def apply_fallback(config:, current_agent:, default_agent:)
          case config.fallback
          when :default_agent
            RoutingDecision.new(
              agent: default_agent,
              confidence: 0,
              reason: :fallback
            )
          when :keep_current
            RoutingDecision.new(
              agent: current_agent || default_agent,
              confidence: 0,
              reason: :kept_current
            )
          when :ask_clarification
            RoutingDecision.new(
              agent: default_agent,
              confidence: 0,
              reason: :needs_clarification,
              inject_instruction: "The user's message was unclear. Please ask them to clarify what they need help with."
            )
          else
            raise InvalidFallbackError, config.fallback
          end
        end
      end
    end
  end
end
