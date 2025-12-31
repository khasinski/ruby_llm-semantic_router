# frozen_string_literal: true

module RubyLLM
  module SemanticRouter
    # Configuration object for the router
    RouterConfig = Struct.new(
      :embedding_model,
      :similarity_threshold,
      :k_neighbors,
      :fallback,
      :default_agent,
      :scope,
      keyword_init: true
    )

    # Main router class that routes messages to specialized agents
    #
    # @example
    #   router = RubyLLM::SemanticRouter::Router.new(
    #     agents: [ProductAgent, AccountAgent],
    #     default_agent: :product
    #   )
    #   router.add_example("Show me products", agent: :product)
    #   router.ask("What laptops do you have?") # Routes to product agent
    #
    class Router
      attr_reader :agents, :current_agent, :last_routing_decision

      # In-memory routing example for non-Rails usage
      InMemoryExample = Struct.new(:agent_name, :example_text, :embedding, keyword_init: true)

      def initialize(
        agents:,
        default_agent:,
        fallback: nil,
        similarity_threshold: nil,
        embedding_model: nil,
        k_neighbors: nil,
        scope: nil,
        strategy: nil,
        examples: nil
      )
        @agents = normalize_agents(agents)
        @default_agent = default_agent.to_sym
        @current_agent = @default_agent
        @strategy = strategy || Strategies::Semantic.new
        @examples = examples || []
        @scope = scope

        validate_default_agent!

        @config = build_config(
          embedding_model: embedding_model,
          similarity_threshold: similarity_threshold,
          k_neighbors: k_neighbors,
          fallback: fallback
        )

        @chat = nil
        @last_routing_decision = nil
      end

      # Send a message to the router and get a response
      #
      # The router will:
      # 1. Determine which agent should handle the message
      # 2. Switch to that agent if needed
      # 3. Forward the message to the agent's chat
      # 4. Return the response
      #
      # @param message [String] The user's message
      # @yield [chunk] Optional block for streaming responses
      # @return [RubyLLM::Message] The response from the selected agent
      def ask(message, &block)
        # Route the message to determine target agent
        @last_routing_decision = route(message)

        # Switch agent if needed
        target_agent = @last_routing_decision.agent
        switch_to(target_agent) if target_agent != @current_agent

        # Handle clarification injection if needed
        if @last_routing_decision.needs_clarification?
          inject_clarification_prompt
        end

        # Forward to the agent's chat
        current_chat.ask(message, &block)
      end

      # Add a routing example
      #
      # @param text [String] Example user message
      # @param agent [Symbol, String] Name of the agent this should route to
      # @return [self]
      def add_example(text, agent:)
        agent_name = agent.to_sym
        validate_agent_exists!(agent_name)

        embedding = generate_embedding(text)

        example = InMemoryExample.new(
          agent_name: agent_name,
          example_text: text,
          embedding: embedding
        )

        @examples << example
        self
      end

      # Import multiple routing examples at once
      # Uses batch embedding for efficiency
      #
      # @param examples [Array<Hash>] Array of {text:, agent:} hashes
      # @return [self]
      def import_examples(examples)
        return self if examples.empty?

        # Validate all agents exist first
        examples.each do |example|
          validate_agent_exists!(example[:agent].to_sym)
        end

        # Batch embed all texts at once
        texts = examples.map { |e| e[:text] }
        embeddings = generate_embeddings_batch(texts)

        # Create examples with pre-computed embeddings
        examples.each_with_index do |example, i|
          @examples << InMemoryExample.new(
            agent_name: example[:agent].to_sym,
            example_text: example[:text],
            embedding: embeddings[i]
          )
        end

        self
      end

      # Preview routing without sending the message
      # Useful for debugging and testing routing decisions
      #
      # @param message [String] The message to test
      # @return [RoutingDecision] What would happen if this message was sent
      def match(message)
        route(message)
      end

      # Get detailed routing info for debugging
      #
      # @param message [String] The message to analyze
      # @return [Hash] Detailed routing information including top matches
      def debug_routing(message)
        embedding = generate_embedding(message)

        matches = if @examples.respond_to?(:nearest_neighbors)
          @examples.nearest_neighbors(:embedding, embedding, distance: :cosine)
                   .limit(@config.k_neighbors * 2) # Get more for debugging
                   .to_a
        else
          find_nearest_in_memory_debug(@examples.to_a, embedding, @config.k_neighbors * 2)
        end

        {
          message: message,
          threshold: @config.similarity_threshold,
          current_agent: @current_agent,
          would_route_to: match(message).agent,
          top_matches: matches.map do |m|
            {
              agent: extract_agent_name_safe(m),
              example: extract_example_text_safe(m),
              confidence: calculate_confidence_safe(m)
            }
          end
        }
      end

      # Get the current chat object
      #
      # @return [RubyLLM::Chat]
      def current_chat
        @chat ||= build_chat_for_agent(@current_agent)
      end

      # Get all messages in the conversation
      #
      # @return [Array<RubyLLM::Message>]
      def messages
        current_chat.messages
      end

      # Get the names of all registered agents
      #
      # @return [Array<Symbol>]
      def agent_names
        @agents.keys
      end

      # Get an agent by name
      #
      # @param name [Symbol, String] Agent name
      # @return [Agent]
      def agent(name)
        @agents[name.to_sym]
      end

      # Get all routing examples
      #
      # @return [Array]
      def examples
        @examples
      end

      # Clear all routing examples
      #
      # @return [self]
      def clear_examples!
        @examples = []
        self
      end

      # Use an external examples source (e.g., ActiveRecord model)
      #
      # @param source [#nearest_neighbors] An object that responds to nearest_neighbors
      # @return [self]
      def with_examples(source)
        @examples = source
        self
      end

      # Manually switch to a specific agent
      #
      # @param agent_name [Symbol, String] Name of the agent to switch to
      # @return [self]
      def switch_to(agent_name)
        agent_name = agent_name.to_sym
        validate_agent_exists!(agent_name)

        return self if agent_name == @current_agent

        agent = @agents[agent_name]

        # Reconfigure the existing chat (preserving history)
        if @chat
          @chat.with_instructions(agent.instructions, replace: true)
          @chat.with_tools(*agent.tools, replace: true) if agent.tools.any?
          @chat.with_model(agent.model) if agent.model
          @chat.with_temperature(agent.temperature) if agent.temperature
        end

        @current_agent = agent_name
        self
      end

      # Register event callbacks
      #
      # @param event [Symbol] Event name (:on_route, :on_switch)
      # @yield Block to call when event occurs
      # @return [self]
      def on(event, &block)
        @callbacks ||= {}
        @callbacks[event] = block
        self
      end

      private

      def route(message)
        decision = @strategy.route(
          message,
          agents: @agents,
          examples: scoped_examples,
          current_agent: @current_agent,
          config: @config
        )

        emit(:on_route, decision)
        decision
      end

      def scoped_examples
        return @examples unless @scope

        if @examples.respond_to?(:where)
          @examples.where(router_scope: @scope)
        else
          @examples.select { |e| e.respond_to?(:router_scope) ? e.router_scope == @scope : true }
        end
      end

      def build_chat_for_agent(agent_name)
        agent = @agents[agent_name]

        chat = RubyLLM.chat
        chat.with_instructions(agent.instructions)
        chat.with_tools(*agent.tools) if agent.tools.any?
        chat.with_model(agent.model) if agent.model
        chat.with_temperature(agent.temperature) if agent.temperature

        chat
      end

      def inject_clarification_prompt
        # Temporarily append clarification instruction
        instruction = @last_routing_decision.inject_instruction
        return unless instruction

        current_instructions = @agents[@current_agent].instructions
        @chat.with_instructions("#{current_instructions}\n\n#{instruction}", replace: true)
      end

      def generate_embedding(text)
        response = RubyLLM.embed(text, model: @config.embedding_model)
        response.vectors.first
      rescue StandardError => e
        raise EmbeddingError, e
      end

      def generate_embeddings_batch(texts)
        # RubyLLM.embed supports batch embedding
        response = RubyLLM.embed(texts, model: @config.embedding_model)
        response.vectors
      rescue StandardError => e
        raise EmbeddingError, e
      end

      def find_nearest_in_memory_debug(examples, query_embedding, k)
        examples.map do |example|
          distance = cosine_distance(query_embedding, example.embedding)
          Strategies::Semantic::InMemoryMatch.new(example, distance)
        end.sort_by(&:distance).first(k)
      end

      def cosine_distance(a, b)
        dot_product = a.zip(b).sum { |x, y| x * y }
        magnitude_a = Math.sqrt(a.sum { |x| x**2 })
        magnitude_b = Math.sqrt(b.sum { |x| x**2 })
        return 1.0 if magnitude_a.zero? || magnitude_b.zero?
        1.0 - (dot_product / (magnitude_a * magnitude_b))
      end

      def extract_agent_name_safe(match)
        match.respond_to?(:agent_name) ? match.agent_name : match.example&.agent_name
      end

      def extract_example_text_safe(match)
        match.respond_to?(:example_text) ? match.example_text : match.example&.example_text
      end

      def calculate_confidence_safe(match)
        distance = match.respond_to?(:neighbor_distance) ? match.neighbor_distance : match.distance
        [1.0 - (distance || 1.0), 0.0].max.round(3)
      end

      def normalize_agents(agents)
        raise NoAgentsError if agents.nil? || agents.empty?

        agents.each_with_object({}) do |agent, hash|
          unless agent.is_a?(Agent)
            raise InvalidAgentError, "Expected Agent, got #{agent.class}"
          end
          hash[agent.name] = agent
        end
      end

      def validate_default_agent!
        return if @agents.key?(@default_agent)

        raise AgentNotFoundError.new(@default_agent, @agents.keys)
      end

      def validate_agent_exists!(agent_name)
        return if @agents.key?(agent_name)

        raise AgentNotFoundError.new(agent_name, @agents.keys)
      end

      def build_config(embedding_model:, similarity_threshold:, k_neighbors:, fallback:)
        global_config = SemanticRouter.configuration || Configuration.new

        RouterConfig.new(
          embedding_model: embedding_model || global_config.default_embedding_model,
          similarity_threshold: similarity_threshold || global_config.default_similarity_threshold,
          k_neighbors: k_neighbors || global_config.default_k_neighbors,
          fallback: fallback || global_config.default_fallback,
          default_agent: @default_agent,
          scope: @scope
        )
      end

      def emit(event, *args)
        @callbacks ||= {}
        @callbacks[event]&.call(*args)
      end
    end
  end
end
