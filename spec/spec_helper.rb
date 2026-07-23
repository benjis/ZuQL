# frozen_string_literal: true

require 'simplecov'

SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
  minimum_coverage line: 90
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'zuql'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
