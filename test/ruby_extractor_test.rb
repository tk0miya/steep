require_relative "test_helper"

class RubyExtractorTest < Minitest::Test
  include Steep

  RubyExtractor = Services::RubyExtractor

  def test_for
    assert_instance_of RubyExtractor::Plain, RubyExtractor.for(Pathname("lib/hello.rb"))
    assert_instance_of RubyExtractor::Erb, RubyExtractor.for(Pathname("lib/hello.erb"))
    assert_instance_of RubyExtractor::HtmlErb, RubyExtractor.for(Pathname("lib/hello.html.erb"))
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
    assert_raises(EncodingError) { RubyExtractor::HtmlErb.new.extract("<%= 1 %>\xff\n") }
  end

  def test_erb__multibyte
    source = "<p>日本語<%= x %></p>\n"
    code = RubyExtractor::Erb.new.extract(source).code

    assert_equal source.size, code.size
    assert_equal source.index("x"), code.index("x")
  end

  def test_html_erb__code
    source = "<p class=\"<%= cls %>\">日本語<% items.each do |i| %><%= i %><% end %></p>\n"
    extracted = RubyExtractor::HtmlErb.new.extract(source)

    # The positions of the characters are kept even if the HTML contains multibyte characters
    assert_equal source.size, extracted.code.size
    assert_equal source.lines.size, extracted.code.lines.size
    assert_equal source.index("cls"), extracted.code.index("cls")
    assert_equal source.index("items"), extracted.code.index("items")
    assert_equal source.index("<% end") + 3, extracted.code.index("end")
  end

  def test_html_erb__multibyte_keeps_separators
    extracted = RubyExtractor::HtmlErb.new.extract("<p>日本語<% a %><% b %></p>\n")

    assert_equal "      ;  a   ;  b       \n", extracted.code
  end

  def test_html_erb__locals
    extracted = RubyExtractor::HtmlErb.new.extract(<<-ERB)
<%# locals: (title:, icon: nil) %><%#: (title: String, icon: String?) %>
<h1><%= title %></h1>
    ERB

    assert_equal [:title, :icon], extracted.locals.keys
    assert_equal ["String", "String?"], extracted.locals.values.map(&:to_s)
  end

  def test_html_erb__locals_in_nested_tag
    extracted = RubyExtractor::HtmlErb.new.extract(<<-ERB)
<div>
  <%# locals: (title:) %>
  <%#: (title: String) %>
  <h1><%= title %></h1>
</div>
    ERB

    assert_equal [:title], extracted.locals.keys
  end

  def test_html_erb__no_locals
    assert_equal({}, RubyExtractor::HtmlErb.new.extract("<h1><%= title %></h1>\n").locals)

    # `local:` is not the declaration
    assert_equal({}, RubyExtractor::HtmlErb.new.extract("<%# local: (title:) %><%#: (title: String) %>\n").locals)
  end

  def test_html_erb__locals_without_types
    # The locals are untyped if the comment of the types is missing
    extracted = RubyExtractor::HtmlErb.new.extract("<%# locals: (title:, icon: nil) %>\n<%= title %>\n")

    assert_equal [:title, :icon], extracted.locals.keys
    assert_equal ["untyped", "untyped"], extracted.locals.values.map(&:to_s)
  end

  def test_html_erb__locals_partially_typed
    extracted = RubyExtractor::HtmlErb.new.extract("<%# locals: (title:, icon: nil) %><%#: (title: String) %>\n")

    assert_equal ["String", "untyped"], extracted.locals.values_at(:title, :icon).map(&:to_s)
  end

  def test_html_erb__locals_keyword_rest
    extracted = RubyExtractor::HtmlErb.new.extract("<%# locals: (title:, **attrs) %>\n")

    assert_equal [:title, :attrs], extracted.locals.keys
  end

  def test_html_erb__invalid_types
    # The locals are untyped if the types are invalid
    extracted = RubyExtractor::HtmlErb.new.extract("<%# locals: (title:) %><%#: (title: ) %>\n<%= title %>\n")

    assert_equal [:title], extracted.locals.keys
    assert_equal ["untyped"], extracted.locals.values.map(&:to_s)
  end

  def test_html_erb__invalid_locals
    assert_equal({}, RubyExtractor::HtmlErb.new.extract("<%# locals: (title: %>\n").locals)
  end

  def test_html_erb__types_requires_hash_colon
    # The types are given by the comment starting with `#:`
    extracted = RubyExtractor::HtmlErb.new.extract("<%# locals: (title:) %><%# (title: String) %>\n")

    assert_equal ["untyped"], extracted.locals.values.map(&:to_s)
  end

  def test_html_erb__ruby_comment
    # `<% # comment %>` is also a comment, like Rails
    extracted = RubyExtractor::HtmlErb.new.extract("<% # locals: (title:) %><% #: (title: String) %>\n<%= title %>\n")

    assert_equal [:title], extracted.locals.keys
    assert_equal ["String"], extracted.locals.values.map(&:to_s)

    extracted = RubyExtractor::HtmlErb.new.extract("<%- # locals: (title:) -%><%#: (title: String) %>\n")

    assert_equal ["String"], extracted.locals.values.map(&:to_s)
  end

  def test_html_erb__locals_in_nested_html
    extracted = RubyExtractor::HtmlErb.new.extract("<div><!-- <%# locals: (title:) %> --></div>\n")

    assert_equal [:title], extracted.locals.keys
  end

  def test_html_erb__multiline_declaration_is_removed
    source = "<% # locals: (title:,\n  icon: nil)\n%>\n<% #: (title: String,\n  icon: String?)\n%>\n<%= title %>\n"
    extracted = RubyExtractor::HtmlErb.new.extract(source)

    assert_equal [:title, :icon], extracted.locals.keys
    assert_equal ["String", "String?"], extracted.locals.values.map(&:to_s)
    assert_equal source.size, extracted.code.size
    assert_equal source.lines.size, extracted.code.lines.size
    assert_equal ["title"], extracted.code.scan(/\w+/)
    assert_equal source.rindex("title"), extracted.code.index("title")
  end

  def test_html_erb__requires_space
    # Rails requires spaces between `#` and `locals:`
    assert_equal({}, RubyExtractor::HtmlErb.new.extract("<%#locals: (title:) %>\n").locals)
  end

  def test_html_erb__locals_boundaries
    html_erb = RubyExtractor::HtmlErb.new

    # Closed with `-%>`
    assert_equal [:a], html_erb.extract("<%# locals: (a:) -%>\n").locals.keys
    # Not closed; the declaration is at the end of the line, like Rails
    assert_equal [:a], html_erb.extract("<%# locals: (a:)\n").locals.keys
    # CRLF
    extracted = html_erb.extract("<%# locals: (a:) %>\r\n<%#: (a: String) %>\r\n<%= a %>\r\n")
    assert_equal ["String"], extracted.locals.values.map(&:to_s)
    # Empty
    assert_equal({}, html_erb.extract("<%# locals: () %>\n").locals)
    # Not keyword parameters
    assert_equal({}, html_erb.extract("<%# locals: (x, y) %>\n").locals.slice(:z))
    # Multiline default values
    extracted = html_erb.extract("<%# locals: (a: 1, b: [1,\n2]) %>\n<%= a %>\n")
    assert_equal [:a, :b], extracted.locals.keys
    assert_equal ["untyped", "untyped"], extracted.locals.values.map(&:to_s)
    assert_equal 3, extracted.code.lines.size
  end

  def test_html_erb__types_comment_boundaries
    html_erb = RubyExtractor::HtmlErb.new

    # Optional keywords
    extracted = html_erb.extract("<%# locals: (a: nil) %><%#: (?a: Integer) %>\n")
    assert_equal ["Integer"], extracted.locals.values.map(&:to_s)
    # Closed with `-%>`
    extracted = html_erb.extract("<%# locals: (a:) %><%#: (a: Integer) -%>\n")
    assert_equal ["Integer"], extracted.locals.values.map(&:to_s)
    # It is not a method type
    extracted = html_erb.extract("<%# locals: (a:) %><%#: (a: Integer) -> void %>\n")
    assert_equal ["untyped"], extracted.locals.values.map(&:to_s)
    # Names that are not declared are ignored
    extracted = html_erb.extract("<%# locals: (a:) %><%#: (a: Integer, b: String) %>\n")
    assert_equal [:a], extracted.locals.keys
  end

  def test_html_erb__types_comment_is_the_next_comment
    html_erb = RubyExtractor::HtmlErb.new

    # Other comments between them
    extracted = html_erb.extract("<%# locals: (a:) %>\n<%# note %>\n<%#: (a: Integer) %>\n")
    assert_equal ["untyped"], extracted.locals.values.map(&:to_s)

    # Other tags between them
    extracted = html_erb.extract("<%# locals: (a:) %><%= a %><%#: (a: Integer) %>\n")
    assert_equal ["Integer"], extracted.locals.values.map(&:to_s)
  end

  def test_html_erb__declaration_is_removed_from_the_code
    source = "<% # locals: (a:) %>\n<% b = 1 %><%# note %>\n<%= a + b %>\n"
    extracted = RubyExtractor::HtmlErb.new.extract(source)

    assert_equal source.size, extracted.code.size
    assert_equal source.lines.size, extracted.code.lines.size
    assert_equal source.index("b = 1"), extracted.code.index("b = 1")
    assert_equal source.index("a + b"), extracted.code.index("a + b")
    assert_equal ["b", "1", "a", "b"], extracted.code.scan(/\w+/)
  end

  def test_html_erb__first_locals
    # Only the first `locals:` is used, like Rails
    extracted = RubyExtractor::HtmlErb.new.extract(<<-ERB)
<%# locals: (a:) %>
<%# comment %>
<%# locals: (b:) %>
<%#: (b: String) %>
    ERB

    assert_equal [:a], extracted.locals.keys
    assert_equal ["untyped"], extracted.locals.values.map(&:to_s)
  end

  def test_extract
    file = Services::TypeCheckService::SourceFile.no_data(path: Pathname("lib/hello.erb"), content: "<%= 1 %>")

    assert_equal ";   1   ", RubyExtractor.extract(file).code
  end
end
