# frozen_string_literal: true

require 'optparse'

module ZuQL
  # Thin command-line adapter for fixture-backed and live interpretation.
  class CLI # rubocop:disable Metrics/ClassLength
    USAGE_ERROR = "Usage error.\n"
    UNSUPPORTED_ERROR = "Unsupported question.\n"
    AMBIGUOUS_ERROR = "Ambiguous concept.\n"
    UNSAFE_ERROR = "Unsafe plan rejected.\n"
    PROVIDER_ERROR = "Provider failed.\n"
    INTERNAL_ERROR = "Internal error.\n"
    EXIT_UNSUPPORTED = 3
    EXIT_AMBIGUOUS = 4
    EXIT_UNSAFE = 5
    EXIT_PROVIDER = 6

    def self.run(argv, out: $stdout, err: $stderr) # rubocop:disable Metrics/MethodLength
      if (argv & %w[--offline --live]).length > 1
        err.write(USAGE_ERROR)
        return 2
      end

      provider = argv.include?('--live') ? Providers::OpenAIProvider.from_env : Providers::FixtureProvider.from_yaml
      interpreter = NaturalLanguageInterpreter.new(provider: provider)
      new(provider: provider, pipeline: Pipeline.new(interpreter: interpreter)).run(argv, out: out, err: err)
    rescue InterpretationProviderError
      err.write(PROVIDER_ERROR)
      EXIT_PROVIDER
    rescue StandardError
      err.write(INTERNAL_ERROR)
      1
    end

    # Renderer and writer injection keeps the command adapter fully testable.
    def initialize( # rubocop:disable Metrics/ParameterLists
      provider:, pipeline:, terminal_renderer: Renderers::TerminalRenderer.new,
      json_renderer: Renderers::JsonRenderer.new, markdown_renderer: Renderers::MarkdownRenderer.new,
      writer: ExclusiveFileWriter.new, support_registry: DomainSupportRegistry.new
    )
      @provider = provider
      @pipeline = pipeline
      @terminal_renderer = terminal_renderer
      @json_renderer = json_renderer
      @markdown_renderer = markdown_renderer
      @writer = writer
      @support_registry = support_registry
    end

    def run(argv, out: $stdout, err: $stderr)
      options, arguments, parser = parse(argv)
      dispatch(options, arguments, parser, out, err)
    rescue StandardError => e
      handle_error(e, err)
    end

    private

    def parse(argv)
      arguments = argv.dup
      options = { json: nil, markdown: nil, information: [], provider_modes: [] }
      parser = parser_for(options)
      parser.parse!(arguments)
      [options, arguments, parser]
    end

    def parser_for(options) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      OptionParser.new do |opts|
        opts.banner = 'Usage: zuql [options] "question"'
        opts.on('--json PATH', 'Export the complete result as JSON') { |path| options[:json] = path }
        opts.on('--markdown PATH', 'Export the explanation as Markdown') { |path| options[:markdown] = path }
        opts.on('--offline', 'Use checked-in interpretation fixtures (default)') do
          options[:provider_modes] << :offline
        end
        opts.on('--live', 'Use the live provider configured by environment') { options[:provider_modes] << :live }
        opts.on('--list-examples', 'List exact offline example questions') { options[:information] << :list }
        opts.on('--list-domains', 'List MVP domain support and limitations') { options[:information] << :domains }
        opts.on('--version', 'Print ZuQL version') { options[:information] << :version }
        opts.on('-h', '--help', 'Show help') { options[:information] << :help }
      end
    end

    def information_requested?(options)
      !options[:information].empty?
    end

    def informational(options, arguments, parser, out, err)
      return usage_error(err) unless valid_information_request?(options, arguments)

      out.write(information_text(options[:information].first, parser))
      0
    end

    def valid_information_request?(options, arguments)
      options[:information].length == 1 && arguments.empty? && !options[:json] && !options[:markdown] &&
        options[:provider_modes].empty?
    end

    def information_text(mode, parser)
      return "#{parser}\n" if mode == :help
      return "#{VERSION}\n" if mode == :version
      return domain_support_text if mode == :domains

      "#{representative_questions.join("\n")}\n"
    end

    def representative_questions
      @support_registry.domains.flat_map { |domain| domain.fetch('representative_questions') }
    end

    def domain_support_text
      @support_registry.domains.map do |domain|
        capabilities = domain.fetch('capabilities').join(', ')
        limitations = domain.fetch('limitations').map { |item| "  - #{item}" }.join("\n")
        [
          "#{domain.fetch('id')} [#{domain.fetch('status')}]",
          "  capabilities: #{capabilities}", '  limitations:', limitations
        ].join("\n")
      end.join("\n") << "\n"
    end

    def valid_query_request?(options, arguments)
      arguments.length == 1 && options[:provider_modes].length <= 1 &&
        (!options[:json] || !options[:markdown] || options[:json] != options[:markdown])
    end

    def execute(question, options, out)
      result = @pipeline.call(question)
      terminal = @terminal_renderer.render(result)
      json = @json_renderer.render(result) if options[:json]
      markdown = @markdown_renderer.render(result) if options[:markdown]
      @writer.write(options[:json], json) if options[:json]
      @writer.write(options[:markdown], markdown) if options[:markdown]
      out.write(terminal)
      0
    end

    def dispatch(options, arguments, parser, out, err)
      return informational(options, arguments, parser, out, err) if information_requested?(options)
      return usage_error(err) unless valid_query_request?(options, arguments)

      execute(arguments.first, options, out)
    end

    def handle_error(error, err)
      message, status = error_response(error)
      err.write(message)
      status
    end

    def error_response(error)
      return [USAGE_ERROR, 2] if error.is_a?(OptionParser::ParseError)
      return [AMBIGUOUS_ERROR, EXIT_AMBIGUOUS] if ambiguous?(error)
      return [UNSUPPORTED_ERROR, EXIT_UNSUPPORTED] if unsupported?(error)
      return [PROVIDER_ERROR, EXIT_PROVIDER] if error.is_a?(InterpretationProviderError)
      return [UNSAFE_ERROR, EXIT_UNSAFE] if unsafe?(error)

      [INTERNAL_ERROR, 1]
    end

    def ambiguous?(error)
      error.is_a?(AmbiguousConceptError) || error.is_a?(AmbiguousJoinPathError)
    end

    def unsupported?(error)
      return true if error.is_a?(UnknownConceptError) || error.is_a?(InvalidQuestionError)

      error.is_a?(InterpretationProviderError) && error.details[:reason] == 'unknown_question'
    end

    def unsafe?(error)
      error.is_a?(PlanningError) || error.is_a?(ValidationError) || error.is_a?(CompilationError)
    end

    def usage_error(err)
      err.write(USAGE_ERROR)
      2
    end
  end
end
