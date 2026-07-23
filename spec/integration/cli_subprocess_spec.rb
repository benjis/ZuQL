# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe 'zuql executable' do
  def run_cli(*arguments)
    Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/zuql', *arguments)
  end

  it 'runs the offline example successfully' do
    stdout, stderr, status = run_cli('Count active subscriptions')
    expect(status.exitstatus).to eq(0)
    expect(stderr).to be_empty
    expect(stdout).to include('COUNT(DISTINCT')
  end

  it 'supports help and example listing' do
    stdout, stderr, status = run_cli('--help')
    expect([status.exitstatus, stderr]).to eq([0, ''])
    expect(stdout).to include('Usage: zuql')

    stdout, stderr, status = run_cli('--list-examples')
    expect([status.exitstatus, stderr]).to eq([0, ''])
    expect(stdout.lines.length).to be >= 14

    stdout, stderr, status = run_cli('--list-domains')
    expect([status.exitstatus, stderr]).to eq([0, ''])
    expect(stdout).to include('product_catalog [partial]', 'invoicing [supported]')
  end

  it 'fails safely for invalid arguments and unsupported questions' do
    _stdout, stderr, status = run_cli('--unknown')
    expect([status.exitstatus, stderr]).to eq([2, "Usage error.\n"])
    stdout, stderr, status = run_cli('Unsupported question')
    expect([status.exitstatus, stdout, stderr]).to eq([3, '', "Unsupported question.\n"])
  end
end
