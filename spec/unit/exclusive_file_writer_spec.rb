# frozen_string_literal: true

require 'tmpdir'

RSpec.describe ZuQL::ExclusiveFileWriter do
  subject(:writer) { described_class.new }

  it 'creates a UTF-8 file without changing the supplied path' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'result.json')
      content = "snowman ☃\n"

      expect(writer.write(path, content)).to equal(path)
      expect(File.read(path, encoding: Encoding::UTF_8)).to eq(content)
    end
  end

  it 'never overwrites an existing file' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'result.json')
      File.write(path, 'original')

      expect { writer.write(path, 'replacement') }.to raise_error(ZuQL::ExportError)
      expect(File.read(path)).to eq('original')
    end
  end
end
