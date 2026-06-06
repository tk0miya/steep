require_relative "test_helper"

# End-to-end tests that drive TypeCheckService with a cache attached, run a
# first check pass, then a second pass to confirm the cache survives correctly
# across runs in the same process. Mirrors what `bin/steep check` does in
# subprocess form, but without spawning workers.
class TypeCheckCacheIntegrationTest < Minitest::Test
  include Steep
  include TestHelper

  ContentChange = Services::ContentChange
  TypeCheckService = Services::TypeCheckService
  TypeCheckCache = Services::TypeCheckCache
  SignatureService = Services::SignatureService

  def with_project_and_cache
    Dir.mktmpdir do |dir|
      base = Pathname(dir)
      (base + "lib").mkdir
      (base + "sig").mkdir

      Dir.chdir(base) do
        project = Project.new(steepfile_path: base + "Steepfile")
        Project::DSL.eval(project) do
          target :main do
            check "lib"
            signature "sig"
          end
        end

        cache = TypeCheckCache.new(cache_dir: base + ".steep_cache")
        yield base, project, cache
      end
    end
  end

  def write(base, rel, content)
    path = base + rel
    path.parent.mkpath
    path.write(content)
  end

  # Helpers analogous to what the worker does: drive update, walk and write env
  # entries, write per-file entries with synthetic LSP payloads.
  def run_check_pass(base, project, cache, files:)
    service = TypeCheckService.new(project: project, cache: cache)

    changes = {}
    files.each do |rel, content|
      changes[Pathname(rel)] = [ContentChange.string(content)]
    end

    service.update(changes: changes)
    service.write_env_cache_for_all_targets
    cache.write_meta

    target = project.targets.first

    rb_paths = files.each_key.select { |k| k.end_with?(".rb") }
    rbs_paths = files.each_key.select { |k| k.end_with?(".rbs") }

    rb_paths.each do |rel|
      path = Pathname(rel)
      content = files[rel]
      diagnostics = service.typecheck_source(path: path, target: target) || []
      lsp = diagnostics.map { |d| { "code" => d.diagnostic_code.to_s } }
      source_file = service.source_files[path]
      next unless source_file && !source_file.outdated
      service.write_source_cache(
        target: target,
        path: path,
        content: content,
        lsp_diagnostics: lsp,
        source_file: source_file
      )
    end

    rbs_paths.each do |rel|
      path = Pathname(rel)
      content = files[rel]
      diagnostics = service.validate_signature(path: path, target: target)
      lsp = diagnostics.map { |d| { "code" => d.diagnostic_code.to_s } }
      signature_file = service.signature_files[target.name][path]
      next unless signature_file
      service.write_signature_cache(
        target: target,
        path: path,
        content: content,
        lsp_diagnostics: lsp,
        signature_file: signature_file
      )
    end

    service
  end

  def test_second_pass_hits_cache_when_nothing_changes
    with_project_and_cache do |base, project, cache|
      files = {
        "sig/a.rbs" => "class A\n  def foo: () -> String\nend\n",
        "lib/a.rb"  => "A.new.foo\n"
      }
      files.each { |rel, content| write(base, rel, content) }

      run_check_pass(base, project, cache, files: files)

      # Second pass: a fresh service should reuse cache for every file.
      service2 = TypeCheckService.new(project: project, cache: cache)
      service2.update(
        changes: files.each_with_object({}) do |(rel, content), h|
          h[Pathname(rel)] = [ContentChange.string(content)]
        end
      )

      target = project.targets.first

      # cached_*_lsp returns the persisted LSP payload when the cache is fresh.
      assert cache_hit_signature?(service2, target, "sig/a.rbs", files.fetch("sig/a.rbs")),
             "sig/a.rbs should be a cache hit"
      assert cache_hit_source?(service2, target, "lib/a.rb", files.fetch("lib/a.rb")),
             "lib/a.rb should be a cache hit"
    end
  end

  # The critical case the persistent cache must get right: a base class is
  # deleted from one file but a subclass elsewhere is unchanged. The cache
  # must still re-check the subclass file.
  def test_deleted_super_class_invalidates_unchanged_subclass
    with_project_and_cache do |base, project, cache|
      files_v1 = {
        "sig/a.rbs" => "class A\n  def foo: () -> String\nend\n",
        "sig/b.rbs" => "class B < A\nend\n",
        "lib/x.rb"  => "B.new\n"
      }
      files_v1.each { |rel, content| write(base, rel, content) }
      run_check_pass(base, project, cache, files: files_v1)

      # Now: A disappears from a.rbs. b.rbs is byte-identical to before.
      files_v2 = files_v1.merge("sig/a.rbs" => "# empty\n")
      files_v2.each { |rel, content| write(base, rel, content) }

      service2 = TypeCheckService.new(project: project, cache: cache)
      service2.update(
        changes: files_v2.each_with_object({}) do |(rel, content), h|
          h[Pathname(rel)] = [ContentChange.string(content)]
        end
      )

      target = project.targets.first

      # Removing A breaks the env (B's super class is now dangling): the
      # signature service ends up in AncestorErrorStatus. The cache must
      # refuse every hit in that target so the new errors are reported.
      refute service2.signature_services[:main].status.is_a?(SignatureService::LoadedStatus),
             "env should be in error state when super class disappears"
      refute cache_hit_signature?(service2, target, "sig/b.rbs", files_v2.fetch("sig/b.rbs")),
             "sig/b.rbs cache must be invalidated by deleted super class"
      refute cache_hit_signature?(service2, target, "sig/a.rbs", files_v2.fetch("sig/a.rbs")),
             "sig/a.rbs cache must be invalidated in error state"
    end
  end

  # The non-erroring counterpart: the base class still exists but a method
  # changed. The signature service stays loaded, so the cache rejects only the
  # changed file and its descendants.
  def test_changed_super_class_signature_invalidates_subclass_via_cached_graph
    with_project_and_cache do |base, project, cache|
      files_v1 = {
        "sig/a.rbs" => "class A\n  def foo: () -> String\nend\n",
        "sig/b.rbs" => "class B < A\nend\n",
        "lib/x.rb"  => "B.new.foo\n"
      }
      files_v1.each { |rel, content| write(base, rel, content) }
      run_check_pass(base, project, cache, files: files_v1)

      # Change A's foo return type. b.rbs is byte-identical.
      files_v2 = files_v1.merge(
        "sig/a.rbs" => "class A\n  def foo: () -> Integer\nend\n"
      )
      files_v2.each { |rel, content| write(base, rel, content) }

      service2 = TypeCheckService.new(project: project, cache: cache)
      service2.update(
        changes: files_v2.each_with_object({}) do |(rel, content), h|
          h[Pathname(rel)] = [ContentChange.string(content)]
        end
      )

      target = project.targets.first
      type_A = RBS::TypeName.new(name: :A, namespace: RBS::Namespace.root)
      type_B = RBS::TypeName.new(name: :B, namespace: RBS::Namespace.root)

      changed = service2.initial_changed_names_for(target.name)
      assert_includes changed, type_A, "changed type must be in changed_names"
      assert_includes changed, type_B, "subclass must propagate via descendants graph"

      refute cache_hit_signature?(service2, target, "sig/b.rbs", files_v2.fetch("sig/b.rbs")),
             "sig/b.rbs depends on A; cache must be invalidated"
    end
  end

  def test_unrelated_change_does_not_invalidate_unrelated_file
    with_project_and_cache do |base, project, cache|
      files = {
        "sig/a.rbs"      => "class A\n  def foo: () -> String\nend\n",
        "sig/widget.rbs" => "class Widget\nend\n",
        "lib/a.rb"       => "A.new.foo\n",
        "lib/widget.rb"  => "Widget.new\n"
      }
      files.each { |rel, content| write(base, rel, content) }
      run_check_pass(base, project, cache, files: files)

      # Touch only sig/a.rbs (change the return type).
      files_v2 = files.merge(
        "sig/a.rbs" => "class A\n  def foo: () -> Integer\nend\n"
      )
      files_v2.each { |rel, content| write(base, rel, content) }

      service2 = TypeCheckService.new(project: project, cache: cache)
      service2.update(
        changes: files_v2.each_with_object({}) do |(rel, content), h|
          h[Pathname(rel)] = [ContentChange.string(content)]
        end
      )

      target = project.targets.first

      # Widget is entirely independent; it must remain a cache hit.
      assert cache_hit_signature?(service2, target, "sig/widget.rbs", files_v2.fetch("sig/widget.rbs")),
             "sig/widget.rbs is unrelated to a.rbs's change"
      assert cache_hit_source?(service2, target, "lib/widget.rb", files_v2.fetch("lib/widget.rb")),
             "lib/widget.rb is unrelated to a.rbs's change"

      refute cache_hit_signature?(service2, target, "sig/a.rbs", files_v2.fetch("sig/a.rbs")),
             "sig/a.rbs changed digest; must miss cache"
    end
  end

  private

  def cache_hit_signature?(service, target, path, content)
    !service.cached_signature_lsp(target: target, path: Pathname(path), content: content).nil?
  end

  def cache_hit_source?(service, target, path, content)
    !service.cached_source_lsp(target: target, path: Pathname(path), content: content).nil?
  end
end
