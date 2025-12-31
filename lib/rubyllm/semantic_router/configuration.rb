# frozen_string_literal: true

module RubyLLM
  module SemanticRouter
    # Global configuration for the semantic router
    class Configuration
      # Default embedding model to use when not specified per-router
      attr_accessor :default_embedding_model

      # Default similarity threshold (0.0 - 1.0)
      attr_accessor :default_similarity_threshold

      # Default number of neighbors to consider for routing
      attr_accessor :default_k_neighbors

      # Default fallback behavior (:default_agent, :keep_current, :ask_clarification)
      attr_accessor :default_fallback

      def initialize
        @default_embedding_model = "text-embedding-3-small"
        @default_similarity_threshold = 0.7
        @default_k_neighbors = 3
        @default_fallback = :default_agent
      end
    end
  end
end
