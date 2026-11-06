require_relative "test_helper"

class PatternTest < Minitest::Test
  include Steep

  def test_pattern
    pattern = Project::Pattern.new(
      patterns: ["app/models", "app/controllers/**/*.rb"],
      ext: ".rb"
    )

    assert_operator pattern, :=~, "app/models/account.rb"
    assert_operator pattern, :=~, "app/controllers/admin_controller.rb"
    assert_operator pattern, :=~, "app/controllers/api/v2/accounts_controller.rb"
  end

  def test_pattern_with_glob
    pattern = Project::Pattern.new(
      patterns: ["app/models/*/bar"],
      ext: ".rb"
    )

    assert_operator pattern, :=~, "app/models/foo/bar/baz.rb"
    assert_operator pattern, :=~, "app/models/foo/bar/baz/qux.rb"
  end

  def test_pattern_with_multiple_exts
    pattern = Project::Pattern.new(
      patterns: ["lib"],
      ext: [".rb", ".rake"]
    )

    assert_equal [".rb", ".rake"], pattern.exts
    assert_operator pattern, :=~, "lib/foo.rb"
    assert_operator pattern, :=~, "lib/tasks/foo.rake"
    refute_operator pattern, :=~, "lib/foo.erb"
  end
end
