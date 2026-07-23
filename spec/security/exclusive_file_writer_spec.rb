# frozen_string_literal: true

require 'tmpdir'

RSpec.describe ZuQL::ExclusiveFileWriter do
  subject(:writer) { described_class.new }

  it 'rejects unsafe path and content values' do
    invalid_path = +"bad\xFF"
    invalid_path.force_encoding(Encoding::UTF_8)
    singleton_path = +'path'
    singleton_path.define_singleton_method(:unsafe?) { true }
    subclass = Class.new(String).new('content').freeze

    ['', invalid_path, singleton_path, Class.new(String).new('path')].each do |path|
      expect { writer.write(path, 'content') }.to raise_error(ZuQL::ExportError)
    end
    [+'mutable', subclass].each do |content|
      expect { writer.write('/tmp/result', content) }.to raise_error(ZuQL::ExportError)
    end
  end

  it 'sanitizes file-system failures and freezes error details' do
    error = nil
    begin
      writer.write('/definitely/missing/private/result', 'content')
    rescue ZuQL::ExportError => e
      error = e
    end

    expect(error.message).to eq('Export failed')
    expect(error.message).not_to include('/definitely')
    expect(error.details).to be_frozen
    expect(error.details.values.join).not_to include('/definitely')
    expect(error.cause).to be_nil
  end

  it 'does not delete a replacement file after a write failure' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'result.txt')
      opened = File.open(path, 'wx:UTF-8') # rubocop:disable Style/FileOpen -- closed by example ensure
      failing = failing_file(opened, path)
      allow(File).to receive(:open) do |*_arguments, &block|
        block.call(failing)
      ensure
        failing.close unless failing.closed?
      end

      expect { writer.write(path, 'content') }.to raise_error(ZuQL::ExportError)
      expect(File.read(path)).to eq('replacement')
    ensure
      opened&.close unless opened&.closed?
    end
  end

  def failing_file(opened, path)
    Object.new.tap do |file|
      file.define_singleton_method(:stat) { opened.stat }
      file.define_singleton_method(:closed?) { opened.closed? }
      file.define_singleton_method(:close) { opened.close }
      file.define_singleton_method(:write) do |_content|
        File.rename(path, "#{path}.partial")
        File.write(path, 'replacement')
        raise IOError, 'simulated failure'
      end
    end
  end
end
