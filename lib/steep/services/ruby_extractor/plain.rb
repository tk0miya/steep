module Steep
  module Services
    module RubyExtractor
      # Ruby files; the content is the Ruby code
      #
      class Plain
        def extract(content)
          Result.new(code: content, locals: {})
        end
      end
    end
  end
end
