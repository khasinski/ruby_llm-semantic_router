# frozen_string_literal: true

begin
  require "ruby_llm"
rescue LoadError
  # ruby_llm not available, will need to be provided externally
end

begin
  require "neighbor"
rescue LoadError
  # neighbor not available, in-memory mode only
end

require_relative "semantic_router/version"
require_relative "semantic_router/errors"
require_relative "semantic_router/configuration"
require_relative "semantic_router/routing_decision"
require_relative "semantic_router/strategies/base"
require_relative "semantic_router/strategies/semantic"
require_relative "semantic_router/router"

module RubyLLM
  module SemanticRouter
    class << self
      attr_accessor :configuration

      def new(**options)
        Router.new(**options)
      end

      def configure
        self.configuration ||= Configuration.new
        yield(configuration) if block_given?
        configuration
      end

      def reset_configuration!
        self.configuration = Configuration.new
      end
    end
  end
end
