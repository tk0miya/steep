module Steep
  module Services
    module RubyExtractor
      # HTML+ERB files, like the views of Rails
      #
      # * The HTML and the ERB tags are removed in the same way as `Erb`
      # * The `locals` are declared with the first `locals:` comment, in the same way as Rails
      # * The types of the `locals` are given by the next comment starting with `#:`, like the inline RBS.
      #   The `locals` without types are `untyped`.
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

          declaration = STRICT_LOCALS.match(content) or return Result.new(code: code, locals: {})

          # The declaration is removed from the code, as Rails does
          removed = [declaration.begin(0)...declaration.end(0)] #: Array[Range[Integer]]
          names = local_names("(#{declaration[1]})")
          types = {} #: Hash[Symbol, RBS::Types::t]

          if names && (comment = COMMENT_TAG.match(content, declaration.end(0))) && TYPES_COMMENT.match?(comment[:body])
            types = local_types(comment[:body])
            removed << ((comment.begin(:body) - 1)...comment.end(:body))
          end

          removed.each do |range|
            code[range] = code[range].to_s.gsub(/[^\n]/, " ")
          end

          Result.new(code: code, locals: locals(names || [], types))
        end

        private

        def locals(names, types)
          names.each.with_object({}) do |name, hash| #$ Hash[Symbol, RBS::Types::t]
            hash[name] = types.fetch(name) { RBS::Types::Bases::Any.new(location: nil) }
          end
        end

        # Names of the keyword parameters of `(title:, icon: nil, **attrs)`
        def local_names(parameters)
          result = Prism.parse("def _#{parameters}; end")
          return unless result.success?

          definition = result.value.statements.body.first
          return unless definition.is_a?(Prism::DefNode)

          params = definition.parameters or return []
          names = params.keywords.map(&:name) #: Array[Symbol]
          rest = params.keyword_rest
          names << rest.name if rest.is_a?(Prism::KeywordRestParameterNode) && rest.name
          names
        end

        # Types in the comment like `#: (title: String, icon: String?)`; empty if the comment is not a valid declaration
        def local_types(comment)
          types = {} #: Hash[Symbol, RBS::Types::t]

          match = TYPES_COMMENT.match(comment) or return types
          function = RBS::Parser.parse_method_type("#{match[1]} -> void").type
          return types unless function.is_a?(RBS::Types::Function)

          function.required_keywords.merge(function.optional_keywords).each do |name, param|
            types[name] = param.type
          end
          types
        rescue RBS::ParsingError
          {}
        end
      end
    end
  end
end
