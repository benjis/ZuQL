# frozen_string_literal: true

require_relative 'lib/zuql/version'

Gem::Specification.new do |spec|
  spec.name = 'zuql'
  spec.version = ZuQL::VERSION
  spec.authors = ['ZuQL contributors']
  spec.summary = 'Deterministic natural-language-to-SQL foundations for Zuora'
  spec.description = spec.summary
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'
  spec.files = Dir[
    'lib/**/*.rb',
    'schemas/*.json',
    'prompts/**/*.txt',
    'data/canonical/**/*.{yml,yaml}',
    'data/fixtures/**/*.{yml,yaml}',
    'data/generated/**/*.{json,md}',
    'exe/*',
    'README.md',
    'LICENSE.txt'
  ]
  spec.require_paths = ['lib']
  spec.bindir = 'exe'
  spec.executables = %w[zuql zuql-audit]

  spec.add_dependency 'dry-struct', '~> 1.6'
  spec.add_dependency 'dry-types', '~> 1.7'
  spec.add_dependency 'dry-validation', '~> 1.11'
  spec.add_dependency 'json_schemer', '~> 2.4'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
