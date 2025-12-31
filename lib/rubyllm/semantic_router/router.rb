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

    # Internal representation of agent config (extracted from chat objects)
    AgentConfig = Struct.new(:name, :instructions, :tools, :model, :temperature, keyword_init: true) do
      def tools
        self[:tools] || []
      end
    end

    # Main router class that routes messages to specialized agents
    #
    # @example
    #   router = RubyLLM::SemanticRouter.new(
    #     agents: {
    #       product: RubyLLM.chat(model: "gpt-4o-mini")
    #                       .with_instructions("You're a product expert..."),
    #       support: RubyLLM.chat(model: "gpt-4o")
    #                       .with_instructions("You help with issues...")
    #                       .with_tools(DiagnosticTool)
    #     },
    #     default_agent: :product
    #   )
    #   router.add_example("Show me products", agent: :product)
    #   router.ask("What laptops do you have?")
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
      # @param message [String] The user's message
      # @yield [chunk] Optional block for streaming responses
      # @return [RubyLLM::Message] The response from the selected agent
      def ask(message, &block)
        @last_routing_decision = route(message)

        target_agent = @last_routing_decision.agent
        switch_to(target_agent) if target_agent != @current_agent

        if @last_routing_decision.needs_clarification?
          inject_clarification_prompt
        end

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

        @examples << InMemoryExample.new(
          agent_name: agent_name,
          example_text: text,
          embedding: embedding
        )
        self
      end

      # Import multiple routing examples at once (batch embedding)
      #
      # @param examples [Array<Hash>] Array of {text:, agent:} hashes
      # @return [self]
      def import_examples(examples)
        return self if examples.empty?

        examples.each { |e| validate_agent_exists!(e[:agent].to_sym) }

        texts = examples.map { |e| e[:text] }
        embeddings = generate_embeddings_batch(texts)

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
      #
      # @param message [String] The message to test
      # @return [RoutingDecision]
      def match(message)
        route(message)
      end

      # Get detailed routing info for debugging
      #
      # @param message [String] The message to analyze
      # @return [Hash]
      def debug_routing(message)
        embedding = generate_embedding(message)

        matches = if @examples.respond_to?(:nearest_neighbors)
          @examples.nearest_neighbors(:embedding, embedding, distance: :cosine)
                   .limit(@config.k_neighbors * 2)
                   .to_a
        else
          find_nearest_in_memory(@examples.to_a, embedding, @config.k_neighbors * 2)
        end

        {
          message: message,
          threshold: @config.similarity_threshold,
          current_agent: @current_agent,
          would_route_to: match(message).agent,
          top_matches: matches.map do |m|
            {
              agent: extract_agent_name(m),
              example: extract_example_text(m),
              confidence: calculate_confidence(m)
            }
          end
        }
      end

      # Get the current chat object
      def current_chat
        @chat ||= build_chat_for_agent(@current_agent)
      end

      # Get all messages in the conversation
      def messages
        current_chat.messages
      end

      # Get the names of all registered agents
      def agent_names
        @agents.keys
      end

      # Get an agent config by name
      def agent(name)
        @agents[name.to_sym]
      end

      # Get all routing examples
      def examples
        @examples
      end

      # Clear all routing examples
      def clear_examples!
        @examples = []
        self
      end

      # Use an external examples source (e.g., ActiveRecord model)
      def with_examples(source)
        @examples = source
        self
      end

      # Manually switch to a specific agent
      def switch_to(agent_name)
        agent_name = agent_name.to_sym
        validate_agent_exists!(agent_name)

        return self if agent_name == @current_agent

        agent = @agents[agent_name]

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
        instruction = @last_routing_decision.inject_instruction
        return unless instruction

        current_instructions = @agents[@current_agent].instructions
        @chat.with_instructions("#{current_instructions}\n\n#{instruction}", replace: true)
      end

      def generate_embedding(text)
        response = RubyLLM.embed(text, model: @config.embedding_model)
        vectors = response.vectors
        # RubyLLM returns the vector directly for single inputs,
        # or wrapped in an array for batch inputs
        vectors.first.is_a?(Array) ? vectors.first : vectors
      rescue StandardError => e
        raise EmbeddingError, e
      end

      def generate_embeddings_batch(texts)
        response = RubyLLM.embed(texts, model: @config.embedding_model)
        vectors = response.vectors
        # For batch, RubyLLM returns array of vectors
        # But if single text was passed, it returns vector directly
        vectors.first.is_a?(Array) ? vectors : [vectors]
      rescue StandardError => e
        raise EmbeddingError, e
      end

      def find_nearest_in_memory(examples, query_embedding, k)
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

      def extract_agent_name(match)
        match.respond_to?(:agent_name) ? match.agent_name : match.example&.agent_name
      end

      def extract_example_text(match)
        match.respond_to?(:example_text) ? match.example_text : match.example&.example_text
      end

      def calculate_confidence(match)
        distance = match.respond_to?(:neighbor_distance) ? match.neighbor_distance : match.distance
        [1.0 - (distance || 1.0), 0.0].max.round(3)
      end

      def normalize_agents(agents)
        raise NoAgentsError if agents.nil? || agents.empty?

        unless agents.is_a?(Hash)
          raise InvalidAgentError, "agents must be a Hash of { name: chat_object }"
        end

        agents.each_with_object({}) do |(name, chat_or_config), hash|
          name = name.to_sym

          # Check if it's a RubyLLM chat object (has with_instructions method)
          if chat_or_config.respond_to?(:with_instructions)
            hash[name] = extract_config_from_chat(name, chat_or_config)
          elsif chat_or_config.is_a?(Hash)
            # Legacy hash format for backwards compatibility
            raise InvalidAgentError, "instructions required for agent :#{name}" unless chat_or_config[:instructions]

            hash[name] = AgentConfig.new(
              name: name,
              instructions: chat_or_config[:instructions],
              tools: Array(chat_or_config[:tools]),
              model: chat_or_config[:model],
              temperature: chat_or_config[:temperature]
            )
          elsif chat_or_config.respond_to?(:instructions)
            # Already an AgentConfig-like object
            hash[name] = chat_or_config
          else
            raise InvalidAgentError, "agent :#{name} must be a RubyLLM.chat object or a config hash"
          end
        end
      end

      def extract_config_from_chat(name, chat)
        # Extract configuration from a RubyLLM chat object
        instructions = extract_instructions(chat)
        raise InvalidAgentError, "agent :#{name} must have instructions (use .with_instructions)" unless instructions

        tools = extract_tools(chat)
        model = extract_model(chat)
        temperature = extract_temperature(chat)

        AgentConfig.new(
          name: name,
          instructions: instructions,
          tools: tools,
          model: model,
          temperature: temperature
        )
      end

      def extract_instructions(chat)
        # Try direct accessor first (for mocks/simple objects)
        return chat.instructions if chat.respond_to?(:instructions) && chat.instructions

        # RubyLLM stores instructions as a system message
        if chat.respond_to?(:messages)
          system_msg = chat.messages.find { |m| m.role == :system }
          if system_msg&.content
            return system_msg.content.respond_to?(:text) ? system_msg.content.text : system_msg.content.to_s
          end
        end

        nil
      end

      def extract_tools(chat)
        return [] unless chat.respond_to?(:tools)

        tools = chat.tools
        case tools
        when Hash then tools.values
        when Array then tools
        else []
        end
      end

      def extract_model(chat)
        return chat.model_id if chat.respond_to?(:model_id) && chat.model_id

        if chat.respond_to?(:model) && chat.model
          model = chat.model
          # RubyLLM returns a Model::Info object, extract the id
          return model.respond_to?(:id) ? model.id : model.to_s
        end

        nil
      end

      def extract_temperature(chat)
        if chat.respond_to?(:temperature_value)
          chat.temperature_value
        elsif chat.respond_to?(:temperature)
          chat.temperature
        else
          chat.instance_variable_get(:@temperature)
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
