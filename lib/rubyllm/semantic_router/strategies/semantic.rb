# frozen_string_literal: true

module RubyLLM
  module SemanticRouter
    module Strategies
      # Semantic routing strategy using embeddings and kNN search
      #
      # This strategy:
      # 1. Generates an embedding for the user's message
      # 2. Finds the nearest routing examples using cosine similarity
      # 3. Routes to the agent associated with the best match
      # 4. Falls back if confidence is below threshold
      class Semantic < Base
        def route(message, agents:, examples:, current_agent:, config:, find_examples: nil, precomputed_embedding: nil)
          # If custom find_examples provided, use it
          # Otherwise, check if we have examples to search
          has_search = find_examples.respond_to?(:call) ||
                       (examples && !examples_empty?(examples))

          unless has_search
            return apply_fallback(
              config: config,
              current_agent: current_agent,
              default_agent: config.default_agent
            )
          end

          # Use precomputed embedding if provided (for batch operations), otherwise generate
          embedding = precomputed_embedding || generate_embedding(message, config.embedding_model, max_words: config.max_words)

          # Find nearest neighbors using custom search or built-in
          matches = if find_examples.respond_to?(:call)
            find_with_custom_search(find_examples, embedding, config.k_neighbors)
          else
            find_nearest_neighbors(examples, embedding, config)
          end

          # No matches found
          if matches.empty?
            return apply_fallback(
              config: config,
              current_agent: current_agent,
              default_agent: config.default_agent
            )
          end

          # Get best match and calculate confidence
          best_match = matches.first
          confidence = calculate_confidence(best_match)

          # Check threshold
          if confidence < config.similarity_threshold
            return apply_fallback(
              config: config,
              current_agent: current_agent,
              default_agent: config.default_agent
            )
          end

          # Return semantic match decision
          RoutingDecision.new(
            agent: extract_agent_name(best_match),
            confidence: confidence,
            matched_example: extract_example_text(best_match),
            reason: :semantic_match
          )
        end

        private

        def examples_empty?(examples)
          if examples.respond_to?(:empty?)
            examples.empty?
          elsif examples.respond_to?(:count)
            examples.count.zero?
          else
            !examples || examples.to_a.empty?
          end
        end

        def generate_embedding(message, model, max_words: nil)
          truncated = truncate_to_max_words(message, max_words)
          response = RubyLLM.embed(truncated, model: model)
          vectors = response.vectors
          # RubyLLM returns vector directly for single input, array of vectors for batch
          vectors.first.is_a?(Array) ? vectors.first : vectors
        rescue StandardError => e
          raise EmbeddingError, e
        end

        def truncate_to_max_words(text, max_words)
          Utils.truncate_to_max_words(text, max_words)
        end

        def find_nearest_neighbors(examples, embedding, config)
          # Support both ActiveRecord (with neighbor gem) and in-memory arrays
          if examples.respond_to?(:nearest_neighbors)
            # ActiveRecord with neighbor gem
            examples.nearest_neighbors(:embedding, embedding, distance: :cosine)
                    .limit(config.k_neighbors)
                    .to_a
          else
            # In-memory array - calculate distances manually
            find_nearest_in_memory(examples.to_a, embedding, config.k_neighbors)
          end
        end

        def find_with_custom_search(find_examples, embedding, limit)
          # Call the custom search function
          results = find_examples.call(embedding, limit: limit)
          return [] if results.nil? || results.empty?

          # Normalize results to have a consistent interface
          results.map do |result|
            CustomSearchMatch.new(result)
          end
        end

        def find_nearest_in_memory(examples, query_embedding, k)
          # Calculate cosine distance for each example
          scored = examples.map do |example|
            distance = cosine_distance(query_embedding, example.embedding)
            [example, distance]
          end

          # Sort by distance (ascending) and take top k
          scored.sort_by { |_, distance| distance }
                .first(k)
                .map { |example, distance| InMemoryMatch.new(example, distance) }
        end

        def cosine_distance(a, b)
          Utils.cosine_distance(a, b)
        end

        def calculate_confidence(match)
          # Convert cosine distance to similarity (confidence)
          # Distance is 0-2 for cosine, similarity is 0-1
          distance = extract_distance(match)
          [1.0 - distance, 0.0].max
        end

        def extract_distance(match)
          if match.respond_to?(:neighbor_distance)
            match.neighbor_distance
          elsif match.respond_to?(:distance)
            match.distance
          else
            1.0 # Maximum distance if we can't determine
          end
        end

        def extract_agent_name(match)
          if match.respond_to?(:agent_name)
            match.agent_name
          elsif match.respond_to?(:example) && match.example.respond_to?(:agent_name)
            match.example.agent_name
          else
            raise Error, "Cannot extract agent_name from match: #{match.inspect}"
          end
        end

        def extract_example_text(match)
          if match.respond_to?(:example_text)
            match.example_text
          elsif match.respond_to?(:example) && match.example.respond_to?(:example_text)
            match.example.example_text
          elsif match.respond_to?(:text)
            match.text
          else
            nil
          end
        end

        # Wrapper for in-memory matches to provide a consistent interface
        class InMemoryMatch
          attr_reader :example, :distance

          def initialize(example, distance)
            @example = example
            @distance = distance
          end

          def agent_name
            example.agent_name
          end

          def example_text
            example.example_text
          end

          def neighbor_distance
            distance
          end
        end

        # Wrapper for custom search results (from find_examples callable)
        # Accepts hashes or objects with agent_name, example_text, distance/score
        class CustomSearchMatch
          attr_reader :result

          def initialize(result)
            @result = result
          end

          def agent_name
            fetch(:agent_name) || fetch(:agent)
          end

          def example_text
            fetch(:example_text) || fetch(:text)
          end

          def distance
            # Support both distance (lower is better) and score (higher is better)
            if (d = fetch(:distance))
              d
            elsif (s = fetch(:score))
              1.0 - s  # Convert score to distance
            else
              0.0
            end
          end

          def neighbor_distance
            distance
          end

          private

          def fetch(key)
            if result.is_a?(Hash)
              result[key] || result[key.to_s]
            elsif result.respond_to?(key)
              result.send(key)
            end
          end
        end
      end
    end
  end
end
