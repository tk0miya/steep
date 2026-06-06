require_relative "test_helper"

class TypeCheckCacheTest < Minitest::Test
  include Steep
  include TestHelper

  TypeCheckCache = Services::TypeCheckCache

  def with_cache_dir
    Dir.mktmpdir do |dir|
      yield TypeCheckCache.new(cache_dir: Pathname(dir))
    end
  end

  def test_meta_compatibility
    with_cache_dir do |cache|
      assert_nil cache.load_meta
      refute cache.meta_compatible?

      cache.write_meta
      meta = cache.load_meta
      refute_nil meta
      assert_equal Steep::VERSION, meta.steep_version
      assert_equal RBS::VERSION, meta.rbs_version
      assert cache.meta_compatible?
    end
  end

  def test_meta_incompatible_when_version_differs
    with_cache_dir do |cache|
      other = TypeCheckCache::Meta.new(
        cache_version: TypeCheckCache::Meta::CURRENT_CACHE_VERSION,
        steep_version: "0.0.0",
        rbs_version: RBS::VERSION
      )
      cache.write_meta(other)
      refute cache.meta_compatible?
    end
  end

  def test_env_entry_roundtrip
    with_cache_dir do |cache|
      type_a = RBS::TypeName.new(name: :A, namespace: RBS::Namespace.root)
      type_b = RBS::TypeName.new(name: :B, namespace: RBS::Namespace.root)

      entry = TypeCheckCache::EnvEntry.new(
        path: Pathname("sig/a.rbs"),
        content_digest: "deadbeef",
        defined_type_names: Set[type_a, type_b],
        direct_ancestors_of: { type_a => Set[type_b] },
        alias_targets_of: {}
      )

      cache.write_env_entry(entry)
      loaded = cache.load_env_entry(Pathname("sig/a.rbs"))

      assert_equal Pathname("sig/a.rbs"), loaded.path
      assert_equal "deadbeef", loaded.content_digest
      assert_equal Set[type_a, type_b], loaded.defined_type_names
      assert_equal Set[type_b], loaded.direct_ancestors_of[type_a]
    end
  end

  def test_signature_entry_roundtrip
    with_cache_dir do |cache|
      type_a = RBS::TypeName.new(name: :A, namespace: RBS::Namespace.root)
      diagnostics = [{ "message" => "demo", "code" => "Ruby::Demo" }]

      entry = TypeCheckCache::SignatureEntry.new(
        path: Pathname("sig/a.rbs"),
        target_name: :main,
        content_digest: "deadbeef",
        referenced_type_names: Set[type_a],
        diagnostics: diagnostics
      )

      cache.write_signature_entry(entry)
      loaded = cache.load_signature_entry(:main, Pathname("sig/a.rbs"))

      assert_equal Pathname("sig/a.rbs"), loaded.path
      assert_equal :main, loaded.target_name
      assert_equal Set[type_a], loaded.referenced_type_names
      assert_equal diagnostics, loaded.diagnostics
    end
  end

  def test_source_entry_roundtrip
    with_cache_dir do |cache|
      type_a = RBS::TypeName.new(name: :A, namespace: RBS::Namespace.root)
      diagnostics = [{ "message" => "demo" }]

      entry = TypeCheckCache::SourceEntry.new(
        path: Pathname("lib/a.rb"),
        target_name: :main,
        content_digest: "cafebabe",
        referenced_type_names: Set[type_a],
        has_unresolved_references: true,
        diagnostics: diagnostics
      )

      cache.write_source_entry(entry)
      loaded = cache.load_source_entry(:main, Pathname("lib/a.rb"))

      assert_equal Pathname("lib/a.rb"), loaded.path
      assert_equal true, loaded.has_unresolved_references
      assert_equal Set[type_a], loaded.referenced_type_names
    end
  end

  def test_each_env_entry_skips_corrupt_files
    with_cache_dir do |cache|
      type_a = RBS::TypeName.new(name: :A, namespace: RBS::Namespace.root)

      entry = TypeCheckCache::EnvEntry.new(
        path: Pathname("sig/a.rbs"),
        content_digest: "x",
        defined_type_names: Set[type_a],
        direct_ancestors_of: {},
        alias_targets_of: {}
      )
      cache.write_env_entry(entry)

      bogus = cache.env_dir + "bogus.bin"
      bogus.binwrite("not a marshal stream")

      collected = cache.each_env_entry.to_a
      assert_equal 1, collected.size
      assert_equal Set[type_a], collected.first.defined_type_names
    end
  end

  def test_clear_removes_all_cache_files
    with_cache_dir do |cache|
      cache.write_meta
      type_a = RBS::TypeName.new(name: :A, namespace: RBS::Namespace.root)
      cache.write_env_entry(
        TypeCheckCache::EnvEntry.new(
          path: Pathname("sig/a.rbs"),
          content_digest: "x",
          defined_type_names: Set[type_a],
          direct_ancestors_of: {},
          alias_targets_of: {}
        )
      )

      assert cache.cache_dir.directory?
      refute_empty cache.cache_dir.children
      cache.clear
      assert cache.cache_dir.directory?
      assert_empty cache.cache_dir.children
    end
  end

  def test_atomic_write_does_not_leave_tempfile
    with_cache_dir do |cache|
      cache.write_meta
      tempfiles = cache.cache_dir.children.select { |c| c.basename.to_s.include?(".tmp.") }
      assert_empty tempfiles
    end
  end

  def test_env_walker_extracts_per_file_info
    Dir.mktmpdir do |dir|
      a_path = Pathname(dir) + "a.rbs"
      b_path = Pathname(dir) + "b.rbs"

      a_path.write(<<~RBS)
        class A
        end

        type t = String | Integer
      RBS

      b_path.write(<<~RBS)
        class B < A
          include Comparable
        end
      RBS

      loader = RBS::EnvironmentLoader.new
      loader.add(path: a_path)
      loader.add(path: b_path)
      env = RBS::Environment.from_loader(loader).resolve_type_names
      builder = RBS::DefinitionBuilder::AncestorBuilder.new(env: env)

      walker = TypeCheckCache::EnvWalker.new(env: env, ancestor_builder: builder)
      buckets = walker.walk

      a_bucket = buckets[a_path]
      refute_nil a_bucket

      type_A = RBS::TypeName.new(name: :A, namespace: RBS::Namespace.root)
      type_B = RBS::TypeName.new(name: :B, namespace: RBS::Namespace.root)
      type_t = RBS::TypeName.parse("::t")

      assert_includes a_bucket[:defined_type_names], type_A
      assert_includes a_bucket[:defined_type_names], type_t

      # B's bucket: includes its direct ancestor A (super) and Comparable (mixin)
      b_bucket = buckets[b_path]
      refute_nil b_bucket
      assert_includes b_bucket[:defined_type_names], type_B
      ancestors_of_B = b_bucket[:direct_ancestors_of][type_B]
      refute_nil ancestors_of_B
      assert_includes ancestors_of_B, type_A
      comparable = RBS::TypeName.new(name: :Comparable, namespace: RBS::Namespace.root)
      assert_includes ancestors_of_B, comparable

      # type alias t targets String and Integer (only what alias_targets captures)
      targets = a_bucket[:alias_targets_of][type_t]
      refute_nil targets
      string_name = RBS::TypeName.new(name: :String, namespace: RBS::Namespace.root)
      integer_name = RBS::TypeName.new(name: :Integer, namespace: RBS::Namespace.root)
      assert_includes targets, string_name
      assert_includes targets, integer_name
    end
  end
end
