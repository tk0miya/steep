require_relative "test_helper"

class RubyExtractorTest < Minitest::Test
  include Steep

  RubyExtractor = Services::RubyExtractor

  def test_for
    assert_instance_of RubyExtractor::Plain, RubyExtractor.for(Pathname("lib/hello.rb"))
    assert_instance_of RubyExtractor::Erb, RubyExtractor.for(Pathname("lib/hello.erb"))
    assert_instance_of RubyExtractor::Erb, RubyExtractor.for(Pathname("lib/hello.html.erb"))
  end

  def test_plain
    extracted = RubyExtractor::Plain.new.extract("1 + 2\n")

    assert_equal "1 + 2\n", extracted.code
    assert_equal({}, extracted.locals)
  end

  def test_erb
    extracted = RubyExtractor::Erb.new.extract(<<-ERB)
<%# comment %>
<% 100.times do |i| %>
  <%= i %>
<% end %>
    ERB

    assert_equal " " * 14 + "\n;  100.times do |i|   \n  ;   i   \n;  end   \n", extracted.code
    assert_equal({}, extracted.locals)
  end

  def test_erb__statements_are_separated
    assert_equal ";  a = 1   ;  b = 2   \n", RubyExtractor::Erb.new.extract("<% a = 1 %><% b = 2 %>\n").code
    assert_equal ";  if x        ;  end   \n", RubyExtractor::Erb.new.extract("<% if x %>hello<% end %>\n").code
  end

  def test_erb__multiline_comment
    code = RubyExtractor::Erb.new.extract("<%# a\n b %>\nz<%= 1 -%>\n<%% x %>\n").code

    assert_equal "     \n     \n ;   1    \n        \n", code
  end

  def test_erb__tags
    erb = RubyExtractor::Erb.new

    assert_equal ";   x  ", erb.extract("<%==x%>").code
    assert_equal ";   x    ", erb.extract("<%- x -%>").code
    assert_equal "   ", erb.extract("<%%").code
    assert_equal "    ", erb.extract("<%%>").code
    assert_equal " " * 9, erb.extract("<%# c -%>").code
  end

  def test_erb__code_keeps_annotation
    # The separator is not put at the end of the tag, so the comments are not polluted
    code = RubyExtractor::Erb.new.extract("<% # @type var x: String %>\n<%= x %>\n").code

    assert_equal ";  # @type var x: String   \n;   x   \n", code
  end

  def test_erb__not_closed_tags
    erb = RubyExtractor::Erb.new

    ["<%= x", "<%-", "<%#", "<%", "a <% b", "<%= 日本語\n"].each do |source|
      code = erb.extract(source).code

      assert_equal source.size, code.size, source
      assert_equal source.lines.size, code.lines.size, source
      assert_equal "", code.delete(" \n"), source
    end
  end

  def test_erb__keeps_lines
    ["a\r\nb<%= 1 %>\r\n", "<% x %>", "日本語<%= x %>日本語\n\n"].each do |source|
      code = RubyExtractor::Erb.new.extract(source).code

      assert_equal source.size, code.size, source
      assert_equal source.lines.size, code.lines.size, source
    end
  end

  def test_erb__invalid_encoding
    assert_raises(EncodingError) { RubyExtractor::Erb.new.extract("<%= 1 %>\xff\n") }
  end

  def test_erb__multibyte
    source = "<p>日本語<%= x %></p>\n"
    code = RubyExtractor::Erb.new.extract(source).code

    assert_equal source.size, code.size
    assert_equal source.index("x"), code.index("x")
  end

  def test_erb__html_code
    source = "<p class=\"<%= cls %>\">日本語<% items.each do |i| %><%= i %><% end %></p>\n"
    extracted = RubyExtractor::Erb.new.extract(source)

    # The positions of the characters are kept even if the HTML contains multibyte characters
    assert_equal source.size, extracted.code.size
    assert_equal source.lines.size, extracted.code.lines.size
    assert_equal source.index("cls"), extracted.code.index("cls")
    assert_equal source.index("items"), extracted.code.index("items")
    assert_equal source.index("<% end") + 3, extracted.code.index("end")
  end

  def test_erb__multibyte_keeps_separators
    extracted = RubyExtractor::Erb.new.extract("<p>日本語<% a %><% b %></p>\n")

    assert_equal "      ;  a   ;  b       \n", extracted.code
  end

  def test_erb__locals
    source = <<-ERB
<%# @type locals: (title: String, ?icon: String?) %>
<h1><%= title %></h1>
    ERB
    extracted = RubyExtractor::Erb.new.extract(source)

    assert_equal({ title: "String", icon: "String?" }, extracted.locals.transform_values(&:to_s))
    assert_empty extracted.errors
    assert_equal ["title"], extracted.code.scan(/\w+/)
    assert_equal source.index("title %>"), extracted.code.index("title")
  end

  def test_erb__no_locals
    assert_equal({}, RubyExtractor::Erb.new.extract("<h1><%= title %></h1>\n").locals)

    # Not an annotation
    assert_equal({}, RubyExtractor::Erb.new.extract("<%# locals: (title: String) %>\n").locals)
    assert_equal({}, RubyExtractor::Erb.new.extract("<%# @type var title: String %>\n").locals)
    # Not a comment
    assert_equal({}, RubyExtractor::Erb.new.extract("<%%# @type locals: (title: String) %>\n").locals)
    assert_equal({}, RubyExtractor::Erb.new.extract("<p># @type locals: (title: String)</p>\n").locals)
  end

  def test_erb__locals_empty
    extracted = RubyExtractor::Erb.new.extract("<%# @type locals: () %>\n")

    assert_equal({}, extracted.locals)
    assert_empty extracted.errors
  end

  def test_erb__locals_ruby_comment
    # `<% # comment %>` is also a comment
    source = "<% # @type locals: (title: String) %>\n<%= title %>\n"
    extracted = RubyExtractor::Erb.new.extract(source)

    assert_equal({ title: "String" }, extracted.locals.transform_values(&:to_s))
    assert_equal source.rindex("title"), extracted.code.rindex("title")

    extracted = RubyExtractor::Erb.new.extract("<%- # @type locals: (title: String) -%>\n")
    assert_equal({ title: "String" }, extracted.locals.transform_values(&:to_s))
  end

  def test_erb__locals_boundaries
    erb = RubyExtractor::Erb.new

    # Closed with `-%>`
    assert_equal [:a], erb.extract("<%# @type locals: (a: String) -%>\n").locals.keys
    # Not closed
    assert_equal({}, erb.extract("<%# @type locals: (a: String)\n").locals)
    # CRLF
    assert_equal [:a], erb.extract("<%# @type locals: (a: String) %>\r\n<%= a %>\r\n").locals.keys
    # Spaces
    assert_equal [:a], erb.extract('<%#@type locals:(a: String)%>').locals.keys
  end

  def test_erb__locals_multiline
    source = "<p>日本語</p>\n<%# @type locals: (title: String,\n  icon: Strin g) %>\n<%= title %>\n"
    extracted = RubyExtractor::Erb.new.extract(source)

    assert_equal({ title: "String", icon: "Strin" }, extracted.locals.transform_values(&:to_s))
    assert_equal source.size, extracted.code.size
    assert_equal source.lines.size, extracted.code.lines.size

    # The locations of the types are in the file
    location = extracted.locals[:icon].location or raise
    assert_equal [3, 8], [location.start_line, location.start_column]
    assert_equal "Strin", location.source
  end

  def test_erb__locals_syntax_error
    # The names of the locals are declared as `untyped`, and the error is reported
    extracted = RubyExtractor::Erb.new.extract("<p>日本語</p>\n<%# @type locals: (title: String, ?icon: ) %>\n")

    assert_equal({ title: "untyped", icon: "untyped" }, extracted.locals.transform_values(&:to_s))
    assert_equal 1, extracted.errors.size
    extracted.errors[0].tap do |error|
      assert_match(/Syntax error/, error.message)
      assert_equal [2, 41], [error.location.start_line, error.location.start_column]
      assert_equal ")", error.location.source
    end

    # Not parameters
    extracted = RubyExtractor::Erb.new.extract("<%# @type locals: String %>\n")
    assert_equal({}, extracted.locals)
    assert_equal 1, extracted.errors.size

    # Not parameters but a method type
    extracted = RubyExtractor::Erb.new.extract("<%# @type locals: (a: Integer) -> void %>\n")
    assert_equal({ a: "untyped" }, extracted.locals.transform_values(&:to_s))
    assert_equal ["->"], extracted.errors.map { _1.location.source }
  end

  def test_erb__locals_not_keywords
    extracted = RubyExtractor::Erb.new.extract("<%# @type locals: (String, ?Integer, *Symbol, title: String, **untyped) %>\n")

    assert_equal({ title: "String" }, extracted.locals.transform_values(&:to_s))
    assert_equal ["String", "Integer", "Symbol", "untyped"], extracted.errors.map { _1.location.source }
    assert_equal ["The locals must be keyword parameters"], extracted.errors.map(&:message).uniq

    extracted = RubyExtractor::Erb.new.extract("<%# @type locals: (?) %>\n")
    assert_equal({}, extracted.locals)
    assert_equal [["The locals must be keyword parameters", "(?)"]], extracted.errors.map { [_1.message, _1.location.source] }
  end

  def test_erb__locals_declared_twice
    # The first declaration is used
    extracted = RubyExtractor::Erb.new.extract(<<-ERB)
<%# @type locals: (a: String) %>
<%# @type locals: (b: Integer) %>
    ERB

    assert_equal({ a: "String" }, extracted.locals.transform_values(&:to_s))
    assert_equal [["The locals are declared already", 2, 18, "(b: Integer)"]], extracted.errors.map { [_1.message, _1.location.start_line, _1.location.start_column, _1.location.source] }
  end

  def test_extract
    file = Services::TypeCheckService::SourceFile.no_data(path: Pathname("lib/hello.erb"), content: "<%= 1 %>")

    assert_equal ";   1   ", RubyExtractor.extract(file).code
  end
end
