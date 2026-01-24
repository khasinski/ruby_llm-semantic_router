# frozen_string_literal: true

module RubyLLM
  module SemanticRouter
    # Simple in-memory cache for embeddings with TTL support
    class EmbeddingCache
      CacheEntry = Struct.new(:embedding, :expires_at, keyword_init: true)

      def initialize(ttl:)
        @ttl = ttl
        @cache = {}
        @mutex = Mutex.new
      end

      # Get embedding from cache
      # @param key [String] Cache key (typically the text that was embedded)
      # @return [Array, nil] Cached embedding or nil if not found/expired
      def get(key)
        @mutex.synchronize do
          entry = @cache[key]
          return nil unless entry
          return nil if entry.expires_at < Time.now

          entry.embedding
        end
      end

      # Store embedding in cache
      # @param key [String] Cache key
      # @param embedding [Array] The embedding vector to cache
      def set(key, embedding)
        @mutex.synchronize do
          @cache[key] = CacheEntry.new(
            embedding: embedding,
            expires_at: Time.now + @ttl
          )
        end
      end

      # Get embedding from cache or compute it
      # @param key [String] Cache key
      # @yield Block that computes the embedding if not cached
      # @return [Array] The embedding
      def fetch(key)
        cached = get(key)
        return cached if cached

        embedding = yield
        set(key, embedding)
        embedding
      end

      # Remove expired entries from cache
      def cleanup!
        @mutex.synchronize do
          now = Time.now
          @cache.delete_if { |_, entry| entry.expires_at < now }
        end
      end

      # Clear all cached entries
      def clear!
        @mutex.synchronize do
          @cache.clear
        end
      end

      # Number of entries in cache
      def size
        @mutex.synchronize { @cache.size }
      end
    end
  end
end
