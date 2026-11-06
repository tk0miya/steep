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
      class Erb
        def extract(content)
          Result.new(code: Scanner.extract(content))
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
