# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require 'zuql'
require 'tmpdir'
require 'yaml'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

task :metadata_audit do
  expected = File.read('data/generated/metadata_audit.json', encoding: Encoding::UTF_8)
  actual = ZuQL::MetadataAudit.new.render
  raise 'Canonical metadata audit is stale; run exe/zuql-audit' unless actual == expected
end

desc 'Run the representative end-to-end MVP golden corpus'
task golden: :spec do
  questions = YAML.safe_load_file('data/fixtures/query_interpretations.yml').fetch('questions')
  raise 'MVP release requires at least 20 golden questions' if questions.length < 20
end

desc 'Build, install, and smoke-test the packaged gem in an isolated GEM_HOME'
task :package_smoke do
  Dir.mktmpdir('zuql-release-') do |directory|
    gem_path = File.join(directory, "zuql-#{ZuQL::VERSION}.gem")
    gem_home = File.join(directory, 'gems')
    sh Gem.ruby, '-S', 'gem', 'build', 'zuql.gemspec', '--output', gem_path
    sh Gem.ruby, '-S', 'gem', 'install', '--no-document', '--install-dir', gem_home, gem_path

    environment = {
      'BUNDLE_GEMFILE' => nil, 'RUBYOPT' => nil, 'RUBYLIB' => nil,
      'GEM_HOME' => gem_home, 'GEM_PATH' => gem_home
    }
    sh environment, File.join(gem_home, 'bin/zuql'), '--help', chdir: directory
    sh environment, File.join(gem_home, 'bin/zuql'), 'Count active subscriptions', chdir: directory
  end
end

desc 'Run every local check required before creating an MVP release tag'
task release_gate: %i[metadata_audit spec rubocop golden package_smoke]

task default: %i[metadata_audit spec rubocop]
