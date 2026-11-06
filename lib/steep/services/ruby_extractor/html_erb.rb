module Steep
  module Services
    module RubyExtractor
      # HTML+ERB files, like the views of Rails
      #
      # * The HTML and the ERB tags are removed in the same way as `Erb`
      # * The `locals` are declared with the first `locals:` comment, in the same way as Rails
      # * The types of the `locals` are given by the next comment starting with `#:`, like the inline RBS.
      #   The `locals` without types are `untyped`, and the type of `**rest` is `Hash[Symbol, T]` for `**T`.
      #   The errors in the types are reported as diagnostics.
      #
      #     <%# locals: (title:, icon: nil) %>
      #     <%#: (title: String, icon: String?) %>
      #
      #   The comment can be a comment of a Ruby code, like `<% # locals: (title:) %>`.
      #
      class HtmlErb
        # The same regexp with Rails; the first match in the source is the declaration
        STRICT_LOCALS = /\#\s+locals:\s+\((.*?)\)(?=\s*-?%>|\s*$)/m

        # A comment tag, `<%# comment %>` or `<% # comment %>`
        #
        # `%>` cannot appear in the Ruby code of an ERB tag, and `<%%#` is not a comment, so the tags are not confused.
        COMMENT_TAG = /<%-?\s*\#(?<body>.*?)-?%>/m

        TYPES_COMMENT = /\A:\s*(\(.*\))\s*\z/m

        def extract(content)
          code = Erb::Scanner.extract(content)

          declaration = STRICT_LOCALS.match(content) or return Result.new(code: code)

          # The declaration is removed from the code, as Rails does
          removed = [declaration.begin(0)...declaration.end(0)] #: Array[Range[Integer]]
          keywords, rest = local_names("(#{declaration[1]})")
          types = {} #: Hash[Symbol, RBS::Types::t]
          errors = [] #: Array[Error]

          if keywords && (comment = COMMENT_TAG.match(content, declaration.end(0))) && (match = TYPES_COMMENT.match(comment[:body]))
            offset = comment.begin(:body) || raise
            types, errors = local_types(content, (offset + match.begin(1))...(offset + match.end(1)), keywords, rest)
            removed << ((offset - 1)...comment.end(:body))
          end

          removed.each do |range|
            code[range] = code[range].to_s.gsub(/[^\n]/, " ")
          end

          names = [*keywords]
          names << rest if rest.is_a?(Symbol)
          Result.new(code: code, locals: locals(names, types), errors: errors)
        end

        private

        def locals(names, types)
          names.each.with_object({}) do |name, hash| #$ Hash[Symbol, RBS::Types::t]
            hash[name] = types.fetch(name) { RBS::Types::Bases::Any.new(location: nil) }
          end
        end

        # Names of the keyword parameters and the keyword rest parameter of `(title:, icon: nil, **attrs)`
        #
        # The name of the keyword rest parameter is `true` if it is anonymous, `**`, and `nil` if it is not declared.
        #
        def local_names(parameters)
          result = Prism.parse("def _#{parameters}; end")
          return unless result.success?

          definition = result.value.statements.body.first
          return unless definition.is_a?(Prism::DefNode)

          params = definition.parameters or return [[], nil]
          keywords = params.keywords.map(&:name) #: Array[Symbol]
          rest = params.keyword_rest
          rest_name =
            if rest.is_a?(Prism::KeywordRestParameterNode)
              rest.name || true
            end
          [keywords, rest_name]
        end

        # Types in the comment like `#: (title: String, icon: String?, **untyped)`
        #
        # `range` is the range of the parameters in `content`. The locations of the types and the errors are in the `content`.
        #
        def local_types(content, range, keywords, rest)
          types = {} #: Hash[Symbol, RBS::Types::t]
          errors = [] #: Array[Error]

          # The text after the parameters is replaced to parse them as a method type, keeping the positions of the parameters
          buffer = RBS::Buffer.new(name: Pathname("(locals)"), content: "#{content[0...range.end]} -> void")
          location = RBS::Location.new(buffer, range.begin, range.end)

          begin
            method_type = RBS::Parser.parse_method_type(buffer, range: range.begin..., require_eof: true) or raise
          rescue RBS::ParsingError => exn
            message = Diagnostic::Signature::SyntaxError.parser_syntax_error_message(exn)
            return [types, [Error.new(message: message, location: exn.location || location)]]
          end

          function = method_type.type

          unless function.is_a?(RBS::Types::Function)
            return [types, [Error.new(message: "The types of the locals must be keyword parameters", location: location)]]
          end

          [
            *function.required_positionals,
            *function.optional_positionals,
            *function.rest_positionals,
            *function.trailing_positionals
          ].each do |param|
            errors << Error.new(message: "The types of the locals must be keyword parameters", location: param.location || location)
          end

          function.required_keywords.merge(function.optional_keywords).each do |name, param|
            if keywords.include?(name)
              types[name] = param.type
            else
              errors << Error.new(message: "`#{name}` is not declared in the locals", location: param.location || location)
            end
          end

          if param = function.rest_keywords
            case rest
            when Symbol
              types[rest] = RBS::Types::ClassInstance.new(
                name: RBS::TypeName.parse("::Hash"),
                args: [RBS::Types::ClassInstance.new(name: RBS::TypeName.parse("::Symbol"), args: [], location: nil), param.type],
                location: nil
              )
            when true
              # The anonymous keyword rest parameter defines no local variable
            else
              errors << Error.new(message: "The keyword rest parameter is not declared in the locals", location: param.location || location)
            end
          end

          [types, errors]
        end
      end
    end
  end
end
