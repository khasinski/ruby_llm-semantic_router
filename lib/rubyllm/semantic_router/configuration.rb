# frozen_string_literal: true

require "logger"

module RubyLLM
  module SemanticRouter
    # Global configuration for the semantic router
    class Configuration
      # Default embedding model to use when not specified per-router
      attr_accessor :default_embedding_model

      # Logger instance for debug output (nil = no logging)
      attr_accessor :logger

      # Embedding cache TTL in seconds (nil = no caching)
      attr_reader :cache_ttl

      # Maximum retry attempts for embedding API failures
      attr_reader :max_retries

      # Base delay in seconds for exponential backoff
      attr_reader :retry_base_delay

      # Default fallback behavior (:default_agent, :keep_current, :ask_clarification)
      attr_reader :default_fallback

      # Default similarity threshold (0.0 - 1.0)
      attr_reader :default_similarity_threshold

      # Default number of neighbors to consider for routing
      attr_reader :default_k_neighbors

      # Default max words to use for embedding (nil = unlimited)
      attr_reader :default_max_words

      VALID_FALLBACKS = %i[default_agent keep_current ask_clarification].freeze

      def initialize
        @default_embedding_model = "text-embedding-3-small"
        @default_similarity_threshold = 0.3
        @default_k_neighbors = 3
        @default_fallback = :default_agent
        @default_max_words = nil
        @logger = nil
        @cache_ttl = nil
        @max_retries = 3
        @retry_base_delay = 0.5
      end

      def cache_ttl=(value)
        return @cache_ttl = nil if value.nil?
        unless value.is_a?(Numeric) && value.positive?
          raise ConfigurationError, "cache_ttl must be nil or a positive number, got: #{value.inspect}"
        end

        @cache_ttl = value
      end

      def max_retries=(value)
        unless value.is_a?(Integer) && value >= 0
          raise ConfigurationError, "max_retries must be a non-negative integer, got: #{value.inspect}"
        end

        @max_retries = value
      end

      def retry_base_delay=(value)
        unless value.is_a?(Numeric) && value.positive?
          raise ConfigurationError, "retry_base_delay must be a positive number, got: #{value.inspect}"
        end

        @retry_base_delay = value
      end

      def default_similarity_threshold=(value)
        validate_similarity_threshold!(value)
        @default_similarity_threshold = value
      end

      def default_k_neighbors=(value)
        validate_k_neighbors!(value)
        @default_k_neighbors = value
      end

      def default_max_words=(value)
        validate_max_words!(value)
        @default_max_words = value
      end

      def default_fallback=(value)
        validate_fallback!(value)
        @default_fallback = value
      end

      private

      def validate_similarity_threshold!(value)
        return if value.is_a?(Numeric) && value >= 0.0 && value <= 1.0

        raise ConfigurationError, "similarity_threshold must be a number between 0.0 and 1.0, got: #{value.inspect}"
      end

      def validate_k_neighbors!(value)
        return if value.is_a?(Integer) && value.positive?

        raise ConfigurationError, "k_neighbors must be a positive integer, got: #{value.inspect}"
      end

      def validate_max_words!(value)
        return if value.nil?
        return if value.is_a?(Integer) && value.positive?

        raise ConfigurationError, "max_words must be nil or a positive integer, got: #{value.inspect}"
      end

      def validate_fallback!(value)
        return if VALID_FALLBACKS.include?(value)

        raise ConfigurationError, "fallback must be one of #{VALID_FALLBACKS.join(', ')}, got: #{value.inspect}"
      end
    end
  end
end
