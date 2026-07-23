# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

RSpec.describe ZuQL::MetadataAudit do
  subject(:audit) { described_class.new }

  it 'produces a deterministic immutable audit of the checked-in registry' do
    first = audit.report
    second = described_class.new.report

    expect(first).to eq(second)
    expect(first).to be_frozen
    expect(first.fetch('status')).to eq('valid')
    expect(first.fetch('counts')).to include(
      'data_sources' => 99, 'objects' => 99, 'relationships' => 25,
      'approved_relationships' => 21, 'metrics' => 9, 'dimensions' => 8, 'domains' => 8
    )
    expect(first.fetch('mapping_status').values.sum).to eq(198)
  end

  it 'validates every checked-in reference and source checksum' do
    expect(audit.validate!).to eq(audit.report)
    expect(audit.report.fetch('errors')).to be_empty
    expect(audit.report.dig('source_checksums', 'extracted_data_sources')).to match(/\A[0-9a-f]{64}\z/)
  end

  it 'reports duplicate IDs, invalid joins, and invalid semantic references' do
    with_registry_copy do |root|
      mutate_yaml(root, 'data/canonical/objects.yml') do |document|
        duplicate = Marshal.load(Marshal.dump(document.fetch('objects').first))
        document.fetch('objects') << duplicate
      end
      mutate_yaml(root, 'data/canonical/relationships.yml') do |document|
        document.fetch('relationships').first.fetch('join')['to_field'] = 'missing'
      end
      mutate_yaml(root, 'data/canonical/metrics.yml') do |document|
        document.fetch('metrics').first['field'] = 'missing.field'
      end

      result = described_class.new(root: root).report
      reasons = result.fetch('errors').map { |error| error.fetch('reason') }

      expect(result.fetch('status')).to eq('invalid')
      expect(reasons).to include('duplicate_id', 'unknown_join_field', 'unknown_semantic_field')
      invalid_audit = described_class.new(root: root)
      first = invalid_audit.report
      expect(invalid_audit.report).to eq(first)
      expect { invalid_audit.validate! }.to raise_error(ZuQL::MetadataValidationError)
    end
  end

  it 'reports stale source artifacts and malformed YAML without leaking paths' do
    with_registry_copy do |root|
      File.open(File.join(root, 'data/extracted/zuora_data_sources.yml'), 'a') { |file| file.write("\n") }
      stale = described_class.new(root: root).report
      expect(stale.fetch('errors').map { |error| error.fetch('reason') }).to include('stale_source_checksum')

      File.write(File.join(root, 'data/canonical/metrics.yml'), "metrics: [\n")
      malformed = described_class.new(root: root).report
      expect(malformed.fetch('errors')).to eq(
        [{ 'reason' => 'malformed_artifact', 'subject' => 'registry', 'detail' => 'Psych::SyntaxError' }]
      )
    end
  end

  def with_registry_copy
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, 'data'))
      FileUtils.cp_r('data/canonical', File.join(root, 'data'))
      FileUtils.cp_r('data/extracted', File.join(root, 'data'))
      FileUtils.cp_r('data/fixtures', File.join(root, 'data'))
      yield root
    end
  end

  def mutate_yaml(root, relative_path)
    path = File.join(root, relative_path)
    document = YAML.safe_load_file(path)
    yield document
    File.write(path, YAML.dump(document))
  end
end
