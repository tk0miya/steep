require_relative "test_helper"

class PatternTest < Minitest::Test
  include Steep

  def test_pattern
    pattern = Project::Pattern.new(
      patterns: ["app/models", "app/controllers/**/*.rb", "app/views/**/*.erb"],
      ext: ".rb"
    )

    assert_operator pattern, :=~, "app/models/account.rb"
    assert_operator pattern, :=~, "app/controllers/admin_controller.rb"
    assert_operator pattern, :=~, "app/controllers/api/v2/accounts_controller.rb"
    assert_operator pattern, :=~, "app/views/accounts/show.erb"
  end

  def test_pattern_with_glob
    pattern = Project::Pattern.new(
      patterns: ["app/models/*/bar"],
      ext: ".rb"
    )

    assert_operator pattern, :=~, "app/models/foo/bar/baz.rb"
    assert_operator pattern, :=~, "app/models/foo/bar/baz/qux.rb"
  end
end
