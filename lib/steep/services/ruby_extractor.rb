module Steep
  module Services
    # Extracts the Ruby code embedded in a file, like ERB templates
    #
    # An extractor is chosen by the path of the file, and has no state.
    # The extracted code keeps the positions of the characters in the file,
    # so the diagnostics are reported on the original position.
    #
    module RubyExtractor
      # The Ruby code of a file, and the local variables defined outside of the code
      #
      Result = _ = Data.define(:code, :locals) do
        # Types of the locals; the names are resolved from the top level, and the type is `untyped` if a name is unknown
        def local_variable_types(factory)
          locals.transform_values do |type|
            unknown = false
            resolved = type.map_type_name do |name|
              factory.absolute_type_name(name, context: nil) || (unknown = true; name)
            end

            unknown ? AST::Types::Any.instance : factory.type(resolved)
          end
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
