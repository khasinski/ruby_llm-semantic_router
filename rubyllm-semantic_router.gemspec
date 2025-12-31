# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "rubyllm/semantic_router/version"

Gem::Specification.new do |spec|
  spec.name          = "rubyllm-semantic_router"
  spec.version       = RubyLLM::SemanticRouter::VERSION
  spec.authors       = ["Chris Hasiński"]
  spec.email         = ["krzysztof.hasinski@gmail.com"]

  spec.summary       = "Semantic routing for RubyLLM multi-agent systems"
  spec.description   = "Route messages to specialized RubyLLM chat agents based on semantic similarity using embeddings and kNN lookup"
  spec.homepage      = "https://github.com/khasinski/ruby_llm-semantic_router"
  spec.license       = "MIT"

  # Note: In production, ruby_llm requires Ruby >= 3.1.0
  # For development/testing, we can use older Ruby with mocks
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  # Note: ruby_llm requires Ruby >= 3.1.0
  # spec.add_dependency "ruby_llm", ">= 1.0"

  # Development dependencies
  spec.add_development_dependency "bundler", ">= 1.17"
  spec.add_development_dependency "rake", ">= 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  # spec.add_development_dependency "neighbor", ">= 0.3"  # Optional: for ActiveRecord tests
end
