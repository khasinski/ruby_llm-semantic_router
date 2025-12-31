# frozen_string_literal: true

module RubyLLM
  module SemanticRouter
    # Value object representing a routing decision
    class RoutingDecision
      # The name of the agent to route to
      attr_reader :agent

      # Confidence score (0.0 - 1.0) of the routing decision
      attr_reader :confidence

      # The example text that matched (for debugging)
      attr_reader :matched_example

      # Reason for the decision (:semantic_match, :fallback, :kept_current, :needs_clarification)
      attr_reader :reason

      # Optional instruction to inject (used for ask_clarification)
      attr_reader :inject_instruction

      def initialize(agent:, confidence: 0.0, matched_example: nil, reason: :semantic_match, inject_instruction: nil)
        @agent = agent&.to_sym
        @confidence = confidence.to_f
        @matched_example = matched_example
        @reason = reason
        @inject_instruction = inject_instruction
      end

      # Returns true if this was a confident semantic match
      def confident?
        reason == :semantic_match && confidence > 0
      end

      # Returns true if this decision used a fallback
      def fallback?
        %i[fallback kept_current needs_clarification].include?(reason)
      end

      # Returns true if clarification is needed
      def needs_clarification?
        reason == :needs_clarification
      end

      def to_h
        {
          agent: agent,
          confidence: confidence,
          matched_example: matched_example,
          reason: reason,
          inject_instruction: inject_instruction
        }.compact
      end

      def ==(other)
        return false unless other.is_a?(RoutingDecision)

        agent == other.agent &&
          confidence == other.confidence &&
          reason == other.reason
      end

      def inspect
        "#<RoutingDecision agent=#{agent.inspect} confidence=#{confidence.round(3)} reason=#{reason.inspect}>"
      end
    end
  end
end
