module Steep
  module Services
    class TypeCheckCache
      # Per-file snapshot of what an env-constituent RBS file contributed last
      # time it was loaded. Stored for every file that goes into env (library
      # RBS, project signatures, inline-from-Ruby). Drives:
      #
      #   * file-set diff (added/removed/changed) via content_digest
      #   * old-side closure expansion (descendants, nested, alias deps) via
      #     defined_type_names + direct_ancestors_of + alias_targets_of
      class EnvEntry
        attr_reader :path,
                    :content_digest,
                    :defined_type_names,
                    :direct_ancestors_of,
                    :alias_targets_of

        def initialize(path:, content_digest:, defined_type_names:, direct_ancestors_of:, alias_targets_of:)
          @path = path
          @content_digest = content_digest
          @defined_type_names = defined_type_names
          @direct_ancestors_of = direct_ancestors_of
          @alias_targets_of = alias_targets_of
        end

        def to_h
          {
            path: path.to_s,
            content_digest: content_digest,
            defined_type_names: defined_type_names,
            direct_ancestors_of: direct_ancestors_of,
            alias_targets_of: alias_targets_of
          }
        end

        def self.from_h(hash)
          new(
            path: Pathname(hash.fetch(:path)),
            content_digest: hash.fetch(:content_digest),
            defined_type_names: hash.fetch(:defined_type_names),
            direct_ancestors_of: hash.fetch(:direct_ancestors_of),
            alias_targets_of: hash.fetch(:alias_targets_of)
          )
        end
      end
    end
  end
end
