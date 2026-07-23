# frozen_string_literal: true

module ZuQL
  # Writes a complete UTF-8 export exactly once and never overwrites a file.
  class ExclusiveFileWriter
    def write(path, content)
      validate!(path, content)
      create(path, content)
      path
    rescue ExportError
      raise
    rescue SystemCallError, IOError, EncodingError => e
      raise ExportError.new(details: { reason: reason_for(e) }), cause: nil
    end

    private

    def create(path, content)
      identity = nil
      File.open(path, 'wx:UTF-8') do |file|
        identity = file_identity(file)
        file.write(content)
      end
    rescue SystemCallError, IOError, EncodingError
      remove_partial(path, identity)
      raise
    end

    def validate!(path, content)
      return if valid_path?(path) && valid_content?(content)

      raise ExportError.new(details: { reason: 'invalid_input' })
    rescue EncodingError
      raise ExportError.new(details: { reason: 'invalid_input' })
    end

    def plain_string?(value)
      value.instance_of?(String) && value.singleton_methods.empty?
    end

    def valid_path?(path)
      plain_string?(path) && path.valid_encoding? && !path.strip.empty?
    end

    def valid_content?(content)
      plain_string?(content) && content.valid_encoding? &&
        content.encoding == Encoding::UTF_8 && content.frozen?
    end

    def file_identity(file)
      stat = file.stat
      [stat.dev, stat.ino]
    end

    def remove_partial(path, identity)
      stat = File.stat(path)
      File.delete(path) if identity && [stat.dev, stat.ino] == identity
    rescue SystemCallError
      nil
    end

    def reason_for(error)
      case error
      when Errno::EEXIST then 'already_exists'
      when Errno::ENOENT then 'missing_parent'
      else 'write_failed'
      end
    end
  end
end
