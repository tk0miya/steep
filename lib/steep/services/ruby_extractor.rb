module Steep
  module Services
    # Extracts the Ruby code embedded in a file, like ERB templates
    #
    # An extractor is chosen by the path of the file, and has no state.
    # The extracted code keeps the positions of the characters in the file,
    # so the diagnostics are reported on the original position.
    #
    module RubyExtractor
      # An error in the declaration of the local variables, like a syntax error of the types
      #
      Error = _ = Data.define(:message, :location)

      # The Ruby code of a file, and the local variables defined outside of the code
      #
      Result = _ = Data.define(:code, :locals, :errors) do
        def initialize(code:, locals: {}, errors: [])
          super
        end

        # Types of the locals
        #
        # The names are resolved from the top level, and the type is `untyped` if it is invalid, like a type with an unknown name.
        #
        def local_variable_types(subtyping)
          resolve_locals(subtyping)[0]
        end

        # Returns the types of the locals, and the diagnostics of the declaration of the locals
        def resolve_locals(subtyping)
          factory = subtyping.factory
          resolver = RBS::Resolver::TypeNameResolver.build(factory.env)

          diagnostics = errors.map do |error|
            Diagnostic::Ruby::AnnotationSyntaxError.new(message: error.message, location: error.location)
          end #: Array[Diagnostic::Ruby::Base]

          types = locals.transform_values do |type|
            resolved = type.map_type_name {|name| resolver.resolve(name, context: nil) || name.absolute! }

            validator = Signature::Validator.new(checker: subtyping)
            validator.rescue_validation_errors { validator.validate_type(resolved) }

            validator.each_error do |error|
              if location = error.location
                diagnostics << Diagnostic::Ruby::RBSError.new(error: error, node: nil, location: location)
              end
            end

            # Deprecated types are still valid
            if validator.each_error.all? { _1.is_a?(Diagnostic::Signature::DeprecatedTypeName) }
              factory.type(resolved)
            else
              AST::Types::Any.instance
            end
          end

          [types, diagnostics]
        end
      end

      # Extracts the Ruby code from a `TypeCheckService::SourceFile`
      def self.extract(source_file)
        self.for(source_file.path).extract(source_file.content)
      end

      def self.for(path)
        case
        when path.to_s.end_with?(".html.erb")
          HtmlErb.new
        when path.extname == ".erb"
          Erb.new
        else
          Plain.new
        end
      end
    end
  end
end
