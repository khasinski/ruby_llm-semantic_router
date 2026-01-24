# frozen_string_literal: true

module RubyLLM
  module SemanticRouter
    # Shared utility methods for semantic routing operations
    module Utils
      module_function

      # Calculate cosine distance between two vectors
      # Cosine distance = 1 - cosine similarity
      # Returns value in range [0, 2] where 0 = identical, 2 = opposite
      #
      # @param a [Array<Numeric>] First vector
      # @param b [Array<Numeric>] Second vector
      # @return [Float] Cosine distance
      def cosine_distance(a, b)
        dot_product = a.zip(b).sum { |x, y| x * y }
        magnitude_a = Math.sqrt(a.sum { |x| x**2 })
        magnitude_b = Math.sqrt(b.sum { |x| x**2 })

        return 1.0 if magnitude_a.zero? || magnitude_b.zero?

        1.0 - (dot_product / (magnitude_a * magnitude_b))
      end

      # Calculate cosine similarity between two vectors
      # Returns value in range [-1, 1] where 1 = identical, -1 = opposite
      #
      # @param a [Array<Numeric>] First vector
      # @param b [Array<Numeric>] Second vector
      # @return [Float] Cosine similarity
      def cosine_similarity(a, b)
        1.0 - cosine_distance(a, b)
      end

      # Truncate text to a maximum number of words
      #
      # @param text [String] Text to truncate
      # @param max_words [Integer, nil] Maximum words (nil = no truncation)
      # @return [String] Truncated text
      def truncate_to_max_words(text, max_words)
        return text unless max_words

        words = text.split
        return text if words.size <= max_words

        words.first(max_words).join(" ")
      end
    end
  end
end
