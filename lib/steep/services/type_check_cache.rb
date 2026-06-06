require "digest"
require "fileutils"

module Steep
  module Services
    # On-disk cache for `bin/steep check`. Layout:
    #
    #   .steep_cache/
    #     meta.bin                                  # format/version guard
    #     env/<target>/<hash>.bin                   # env-constituent file snapshots
    #     signatures/<target>/<relative>.bin        # project signature validation results
    #     sources/<target>/<relative>.bin           # source type-check results
    #
    # Each target stores its own env snapshots because targets can configure
    # different library sets. Per-target also makes cleanup straightforward
    # when a target is removed from Steepfile.
    class TypeCheckCache
      ENV_DIR = "env".freeze
      SIGNATURES_DIR = "signatures".freeze
      SOURCES_DIR = "sources".freeze
      META_FILE = "meta.bin".freeze

      attr_reader :cache_dir

      def initialize(cache_dir:)
        @cache_dir = Pathname(cache_dir)
      end

      # --- meta -------------------------------------------------------------

      def meta_path
        cache_dir + META_FILE
      end

      def load_meta
        return nil unless meta_path.exist?
        data = read_marshal(meta_path)
        return nil unless data.is_a?(Hash)
        Meta.from_h(data)
      rescue StandardError
        nil
      end

      def write_meta(meta = Meta.current)
        ensure_dir(cache_dir)
        write_marshal(meta_path, meta.to_h)
      end

      def meta_compatible?
        existing = load_meta or return false
        existing.compatible_with?(Meta.current)
      end

      # --- env entries (per target) ----------------------------------------

      def env_dir_for(target_name)
        cache_dir + ENV_DIR + target_name.to_s
      end

      def env_entry_path(target_name, path)
        env_dir_for(target_name) + "#{Digest::SHA256.hexdigest(path.to_s)}.bin"
      end

      def load_env_entry(target_name, path)
        file = env_entry_path(target_name, path)
        return nil unless file.exist?
        data = read_marshal(file)
        return nil unless data.is_a?(Hash)
        EnvEntry.from_h(data)
      rescue StandardError
        nil
      end

      def write_env_entry(target_name, entry)
        ensure_dir(env_dir_for(target_name))
        write_marshal(env_entry_path(target_name, entry.path), entry.to_h)
      end

      def each_env_entry(target_name, &block)
        return enum_for(:each_env_entry, target_name) unless block
        dir = env_dir_for(target_name)
        return unless dir.directory?
        dir.each_child do |file|
          next unless file.file? && file.extname == ".bin"
          data =
            begin
              read_marshal(file)
            rescue StandardError
              next
            end
          next unless data.is_a?(Hash)
          yield EnvEntry.from_h(data)
        end
      end

      # --- signature entries -----------------------------------------------

      def signature_entry_path(target_name, path)
        cache_dir + SIGNATURES_DIR + target_name.to_s + relative_bin_path(path)
      end

      def load_signature_entry(target_name, path)
        file = signature_entry_path(target_name, path)
        return nil unless file.exist?
        data = read_marshal(file)
        return nil unless data.is_a?(Hash)
        SignatureEntry.from_h(data)
      rescue StandardError
        nil
      end

      def write_signature_entry(entry)
        file = signature_entry_path(entry.target_name, entry.path)
        ensure_dir(file.parent)
        write_marshal(file, entry.to_h)
      end

      # --- source entries --------------------------------------------------

      def source_entry_path(target_name, path)
        cache_dir + SOURCES_DIR + target_name.to_s + relative_bin_path(path)
      end

      def load_source_entry(target_name, path)
        file = source_entry_path(target_name, path)
        return nil unless file.exist?
        data = read_marshal(file)
        return nil unless data.is_a?(Hash)
        SourceEntry.from_h(data)
      rescue StandardError
        nil
      end

      def write_source_entry(entry)
        file = source_entry_path(entry.target_name, entry.path)
        ensure_dir(file.parent)
        write_marshal(file, entry.to_h)
      end

      # --- bulk ops --------------------------------------------------------

      def clear
        return unless cache_dir.directory?
        cache_dir.each_child do |child|
          FileUtils.rm_rf(child.to_s)
        end
      end

      def self.digest_content(content)
        Digest::SHA256.hexdigest(content)
      end

      # Computes the changed_type_names set for a target given its new env and
      # the previously cached env entries. Used at startup to decide which
      # files can reuse their cached diagnostics.
      #
      # The closure expansion mirrors SignatureService#update_builder, but
      # substitutes the cached EnvEntry collection for the old env that
      # #update_builder would otherwise read directly from memory.
      def compute_changed_names(target_name:, new_env:, new_ancestor_builder:)
        old_entries = each_env_entry(target_name).to_a
        old_by_path = old_entries.each_with_object({}) { |e, h| h[e.path] = e }

        new_paths = collect_env_paths(new_env)
        new_digests = compute_new_digests(new_paths)

        changed_paths = Set[]

        # Added or modified files.
        new_paths.each do |path|
          digest = new_digests[path] or next
          cached = old_by_path[path]
          if cached.nil? || cached.content_digest != digest
            changed_paths << path
          end
        end

        # Files cached previously but absent in new env (removed/renamed).
        old_by_path.each_key do |path|
          changed_paths << path unless new_paths.include?(path)
        end

        # Seed with names defined by changed files in both old and new env.
        changed_names = Set[] #: Set[RBS::TypeName]
        changed_paths.each do |path|
          if (cached = old_by_path[path])
            changed_names.merge(cached.defined_type_names)
          end
          if new_paths.include?(path)
            changed_names.merge(collect_defined_type_names_in_path(new_env, path))
          end
        end

        # Closure: old side (rebuilt from cache) and new side (live env).
        old_descendants = build_old_descendants(old_entries)
        old_alias_targets = build_old_alias_targets(old_entries)
        old_universe = old_entries.each_with_object(Set[]) { |e, set| set.merge(e.defined_type_names) }

        expand_descendants_cached(changed_names, old_descendants)
        expand_descendants_new(changed_names, new_env, new_ancestor_builder)

        expand_nested(changed_names, old_universe)
        expand_nested(changed_names, new_env_universe(new_env))

        expand_alias_dependencies_cached(changed_names, old_alias_targets)
        expand_alias_dependencies_new(changed_names, new_env)

        changed_names
      end

      private

      def read_marshal(file)
        Marshal.load(file.binread)
      end

      def write_marshal(file, data)
        tmp = file.sub_ext(".bin.tmp.#{Process.pid}.#{rand(1_000_000)}")
        tmp.binwrite(Marshal.dump(data))
        File.rename(tmp.to_s, file.to_s)
      end

      def ensure_dir(dir)
        FileUtils.mkdir_p(dir.to_s)
      end

      def relative_bin_path(path)
        path = Pathname(path)
        rel =
          if path.absolute?
            digest = Digest::SHA256.hexdigest(path.to_s)
            "#{digest}_#{path.basename}"
          else
            path.to_s
          end
        Pathname("#{rel}.bin")
      end

      def collect_env_paths(env)
        paths = Set[]
        env.buffers.each do |buffer|
          paths << Pathname(buffer.name)
        end
        paths
      end

      def compute_new_digests(paths)
        paths.each_with_object({}) do |path, h|
          h[path] = self.class.digest_content(path.binread) if path.file?
        end
      end

      def collect_defined_type_names_in_path(env, path)
        set = Set[]
        env.class_decls.each do |type_name, entry|
          entry.each_decl do |decl|
            if decl.location&.buffer&.name && Pathname(decl.location.buffer.name) == path
              set << type_name
            end
          end
        end
        env.interface_decls.each do |type_name, entry|
          if entry.decl.location&.buffer&.name && Pathname(entry.decl.location.buffer.name) == path
            set << type_name
          end
        end
        env.type_alias_decls.each do |type_name, entry|
          if entry.decl.location&.buffer&.name && Pathname(entry.decl.location.buffer.name) == path
            set << type_name
          end
        end
        env.class_alias_decls.each do |type_name, entry|
          if entry.decl.location&.buffer&.name && Pathname(entry.decl.location.buffer.name) == path
            set << type_name
          end
        end
        set
      end

      # Inverts direct_ancestors_of (defined → ancestors) to (ancestor → defined),
      # then takes transitive closure on demand via #expand_descendants_cached.
      def build_old_descendants(entries)
        graph = {}
        entries.each do |entry|
          entry.direct_ancestors_of.each do |defined, ancestors|
            ancestors.each do |anc|
              (graph[anc] ||= Set[]) << defined
            end
          end
        end
        graph
      end

      def build_old_alias_targets(entries)
        targets_by_alias = {}
        entries.each do |entry|
          entry.alias_targets_of.each do |alias_name, targets|
            targets_by_alias[alias_name] = targets
          end
        end
        targets_by_alias
      end

      def expand_descendants_cached(set, graph)
        return if graph.empty?
        queue = set.to_a
        until queue.empty?
          name = queue.shift
          (graph[name] || Set[]).each do |descendant|
            if set.add?(descendant)
              queue << descendant
            end
          end
        end
      end

      def expand_descendants_new(set, env, ancestor_builder)
        graph = RBS::AncestorGraph.new(env: env, ancestor_builder: ancestor_builder)
        set.to_a.each do |name|
          case
          when name.interface?
            graph.each_descendant(RBS::AncestorGraph::InstanceNode.new(type_name: name)) do |node|
              set << node.type_name
            end
          when name.class?
            graph.each_descendant(RBS::AncestorGraph::InstanceNode.new(type_name: name)) do |node|
              set << node.type_name
            end
            graph.each_descendant(RBS::AncestorGraph::SingletonNode.new(type_name: name)) do |node|
              set << node.type_name
            end
          end
        end
      rescue StandardError
        # A malformed env still lets us deliver the cached-side expansion above;
        # the new-side gap is widened later by SignatureService runtime work.
      end

      def expand_nested(set, universe_or_env)
        names_snapshot = set.to_a
        tops = Set[]
        names_snapshot.each do |name|
          unless name.namespace.empty?
            tops << name.namespace.path[0]
          end
        end
        return if tops.empty?

        each_universe_name(universe_or_env) do |name|
          unless name.namespace.empty?
            if tops.include?(name.namespace.path[0])
              set << name
            end
          end
        end
      end

      def each_universe_name(universe_or_env, &block)
        case universe_or_env
        when Set
          universe_or_env.each(&block)
        else
          universe_or_env.class_decls.each_key(&block)
          universe_or_env.interface_decls.each_key(&block)
        end
      end

      def new_env_universe(env)
        env
      end

      def expand_alias_dependencies_cached(set, targets_by_alias)
        # Invert: target_type → set of aliases referencing it.
        referenced_by = {}
        targets_by_alias.each do |alias_name, targets|
          targets.each do |t|
            (referenced_by[t] ||= Set[]) << alias_name
          end
        end

        queue = set.to_a
        until queue.empty?
          name = queue.shift
          (referenced_by[name] || Set[]).each do |alias_name|
            if set.add?(alias_name)
              queue << alias_name
            end
          end
        end
      end

      def expand_alias_dependencies_new(set, env)
        referenced_by = {}
        env.type_alias_decls.each do |alias_name, entry|
          each_type_name_in(entry.decl.type) do |t|
            (referenced_by[t] ||= Set[]) << alias_name
          end
        end

        queue = set.to_a
        until queue.empty?
          name = queue.shift
          (referenced_by[name] || Set[]).each do |alias_name|
            if set.add?(alias_name)
              queue << alias_name
            end
          end
        end
      end

      def each_type_name_in(type, &block)
        case type
        when RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Interface, RBS::Types::Alias
          yield type.name
        end

        type.each_type do |child|
          each_type_name_in(child, &block)
        end
      end
    end
  end
end
