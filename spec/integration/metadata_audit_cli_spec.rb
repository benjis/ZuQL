# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe 'zuql-audit executable' do
  it 'prints the deterministic valid report and exits successfully' do
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/zuql-audit')
    report = JSON.parse(stdout)

    expect(status.exitstatus).to eq(0)
    expect(stderr).to be_empty
    expect(report.fetch('status')).to eq('valid')
    expect(report.fetch('errors')).to be_empty
    expect(stdout).to eq(ZuQL::MetadataAudit.new.render)
  end
end
