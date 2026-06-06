module Steep
  module Services
    class TypeCheckCache
      # Walks an RBS::Environment and groups declarations by their source file
      # buffer name, extracting the per-file information needed to reconstruct
      # the "old" ancestor graph and alias-dependency map at startup.
      #
      # The output is a Hash keyed by Pathname (buffer name) whose value is an
      # EnvEntry-shaped record (defined_type_names, direct_ancestors_of,
      # alias_targets_of). Content digests are filled in by the caller.
      class EnvWalker
        attr_reader :env, :ancestor_builder

        def initialize(env:, ancestor_builder:)
          @env = env
          @ancestor_builder = ancestor_builder
        end

        # Returns: Hash[Pathname, { defined_type_names:, direct_ancestors_of:, alias_targets_of: }]
        def walk
          # @type var buckets: Hash[Pathname, EnvWalker::bucket]
          buckets = {}

          walk_class_decls(buckets)
          walk_interface_decls(buckets)
          walk_type_alias_decls(buckets)
          walk_class_alias_decls(buckets)

          buckets
        end

        private

        def bucket_for(buckets, path)
          existing = buckets[path]
          return existing if existing

          direct = {} #: Hash[RBS::TypeName, Set[RBS::TypeName]]
          targets = {} #: Hash[RBS::TypeName, Set[RBS::TypeName]]
          buckets[path] = {
            defined_type_names: Set[],
            direct_ancestors_of: direct,
            alias_targets_of: targets
          }
        end

        def walk_class_decls(buckets)
          env.class_decls.each do |type_name, entry|
            ancestors_set = collect_class_ancestors(type_name)

            entry.each_decl do |decl|
              path = decl_path(decl)
              next unless path
              bucket = bucket_for(buckets, path)
              bucket[:defined_type_names] << type_name
              # Several decls of the same class may live in different files; each
              # records the (identical) direct-ancestor set so any file's removal
              # still reveals the ancestor relationship in the cached data.
              bucket[:direct_ancestors_of][type_name] = ancestors_set
            end
          end
        end

        def walk_interface_decls(buckets)
          env.interface_decls.each do |type_name, entry|
            ancestors_set = collect_interface_ancestors(type_name)
            decl = entry.decl
            path = decl_path(decl)
            next unless path
            bucket = bucket_for(buckets, path)
            bucket[:defined_type_names] << type_name
            bucket[:direct_ancestors_of][type_name] = ancestors_set
          end
        end

        def walk_type_alias_decls(buckets)
          env.type_alias_decls.each do |type_name, entry|
            decl = entry.decl
            path = decl_path(decl)
            next unless path
            bucket = bucket_for(buckets, path)
            bucket[:defined_type_names] << type_name
            targets = Set[]
            each_type_name_in(decl.type) { |n| targets << n }
            bucket[:alias_targets_of][type_name] = targets
          end
        end

        def walk_class_alias_decls(buckets)
          env.class_alias_decls.each do |type_name, entry|
            decl = entry.decl
            path = decl_path(decl)
            next unless path
            bucket = bucket_for(buckets, path)
            bucket[:defined_type_names] << type_name
            # An alias points at exactly one other name; that target is the only
            # "ancestor" relationship a change can flow through.
            bucket[:direct_ancestors_of][type_name] = Set[decl.old_name]
          end
        end

        def collect_class_ancestors(type_name)
          set = Set[] #: Set[RBS::TypeName]

          instance = safe_one_ancestors(:instance, type_name)
          if instance
            if (sc = instance.super_class).is_a?(RBS::Definition::Ancestor::Instance)
              set << sc.name
            end
            instance.included_modules&.each { |a| set << a.name }
            instance.prepended_modules&.each { |a| set << a.name }
            instance.self_types&.each { |a| set << a.name }
          end

          singleton = safe_one_ancestors(:singleton, type_name)
          if singleton
            if (sc = singleton.super_class).is_a?(RBS::Definition::Ancestor::Singleton)
              set << sc.name
            end
            singleton.extended_modules&.each { |a| set << a.name }
          end

          set
        end

        def collect_interface_ancestors(type_name)
          set = Set[] #: Set[RBS::TypeName]
          ancestors = safe_one_ancestors(:interface, type_name)
          if ancestors
            ancestors.included_interfaces&.each { |a| set << a.name }
          end
          set
        end

        def safe_one_ancestors(kind, type_name)
          case kind
          when :instance
            ancestor_builder.one_instance_ancestors(type_name)
          when :singleton
            ancestor_builder.one_singleton_ancestors(type_name)
          when :interface
            ancestor_builder.one_interface_ancestors(type_name)
          end
        rescue RBS::BaseError
          # A broken signature surfaces as a diagnostic elsewhere; here we just
          # skip the missing relationships so the rest of the cache still builds.
          nil
        end

        def decl_path(decl)
          loc = decl.location or return nil
          buffer = loc.buffer or return nil
          Pathname(buffer.name)
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
end
