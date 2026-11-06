module Steep
  module Services
    module RubyExtractor
      # ERB files; everything but the Ruby code of the ERB tags is replaced with spaces
      #
      # * `<%= code %>` and `<% code %>` are replaced with `;  code  ` to separate the statements
      # * `<%# comment %>` is replaced with spaces, including the lines of the multi-line comments
      # * `<%%` is a literal `<%`, which is not a tag
      #
      # The length and the lines are kept, so the positions of the characters are kept.
      #
      # The local variables given to the template, like `ERB#result_with_hash`, are declared with a comment tag:
      #
      #     <%# @type locals: (title: String, ?icon: String?) %>
      #
      # The comment can be a comment of a Ruby code, like `<% # @type locals: (title: String) %>`.
      # The types are keyword parameters of RBS, and the errors are reported as diagnostics.
      #
      class Erb
        # A comment tag, `<%# comment %>` or `<% # comment %>`
        #
        # `%>` cannot appear in the Ruby code of an ERB tag, and `<%%#` is not a comment, so the tags are not confused.
        COMMENT_TAG = /<%-?\s*\#(?<body>.*?)-?%>/m

        LOCALS_ANNOTATION = /\A\s*@type\s+locals\s*:\s*(?<params>.*?)\s*\z/m

        def extract(content)
          code = Scanner.extract(content)
          locals = {} #: Hash[Symbol, RBS::Types::t]
          errors = [] #: Array[Error]
          declared = false

          content.scan(COMMENT_TAG) do
            comment = Regexp.last_match or raise
            match = LOCALS_ANNOTATION.match(comment[:body] || raise) or next

            offset = comment.begin(:body) || raise
            range = (offset + (match.begin(:params) || raise))...(offset + (match.end(:params) || raise))

            if declared
              buffer = RBS::Buffer.new(name: Pathname("(locals)"), content: content)
              errors << Error.new(message: "The locals are declared already", location: RBS::Location.new(buffer, range.begin, range.end))
            else
              declared = true
              locals, errors = local_types(content, range)
            end
          end

          Result.new(code: code, locals: locals, errors: errors)
        end

        private

        # Types of the locals in `range` of `content`, like `(title: String, ?icon: String?)`
        #
        # The locations of the types and the errors are in the `content`.
        # The names of the locals are still declared as `untyped` if the types have a syntax error.
        #
        def local_types(content, range)
          types = {} #: Hash[Symbol, RBS::Types::t]
          errors = [] #: Array[Error]

          # The text after the parameters is replaced to parse them as a method type, keeping the positions of the parameters
          buffer = RBS::Buffer.new(name: Pathname("(locals)"), content: "#{content[0...range.end]} -> void")
          location = RBS::Location.new(buffer, range.begin, range.end)

          begin
            method_type = RBS::Parser.parse_method_type(buffer, range: range.begin..., require_eof: true) or raise
          rescue RBS::ParsingError => exn
            message = Diagnostic::Signature::SyntaxError.parser_syntax_error_message(exn)
            location.source.scan(/(?:\A\(|,)\s*\??([a-z_]\w*)\s*:/) do |name,|
              types[name.to_sym] = RBS::Types::Bases::Any.new(location: nil)
            end
            return [types, [Error.new(message: message, location: exn.location || location)]]
          end

          function = method_type.type

          unless function.is_a?(RBS::Types::Function)
            return [types, [Error.new(message: "The locals must be keyword parameters", location: location)]]
          end

          [
            *function.required_positionals,
            *function.optional_positionals,
            *function.rest_positionals,
            *function.trailing_positionals,
            *function.rest_keywords
          ].each do |param|
            errors << Error.new(message: "The locals must be keyword parameters", location: param.location || location)
          end

          function.required_keywords.merge(function.optional_keywords).each do |name, param|
            types[name] = param.type
          end

          [types, errors]
        end

        class Scanner
          def self.extract(content)
            # Raises `EncodingError` like the Ruby parser, instead of `ArgumentError` from the regexp
            raise EncodingError, "invalid byte sequence in #{content.encoding}" unless content.valid_encoding?

            new(content).extract
          end

          def initialize(content)
            @scanner = StringScanner.new(content)
            @result = +''
          end

          def extract
            until scanner.eos?
              if scanner.scan(/<%(?!%)/)
                scan_tag
              else
                blank(scanner.scan(/<%%|[^<]+|</) || raise)
              end
            end

            @result
          end

          private

          attr_reader :scanner

          # Appends spaces for the text; the newlines are kept
          def blank(text)
            @result << text.gsub(/[^\n]/, ' ')
          end

          def scan_tag
            opening = scanner.scan(/==|[=\-#]/)
            body = scanner.scan_until(/%>/)

            if body.nil?
              # The tag is not closed
              blank("<%#{opening}#{scanner.rest}")
              scanner.terminate
            elsif opening == "#"
              blank("<%#{opening}#{body}")
            else
              code = body.delete_suffix("%>")
              hyphen = code.end_with?("-")
              code = code.delete_suffix("-") if hyphen

              # Statements are separated by `;` at the beginning of the tag, not at the end,
              # because the end of the tag may be in a comment (`<% # @type var x: String %>`)
              @result << ";" << (" " * ("<%#{opening}".size - 1))
              @result << code
              @result << (hyphen ? '   ' : '  ')
            end
          end
        end
      end
    end
  end
end
